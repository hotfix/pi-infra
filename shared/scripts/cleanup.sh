#!/bin/bash
# =============================================================================
# cleanup.sh – Speicher & Logs bereinigen
# Empfohlener Cron: 0 4 * * 0 sudo /home/pi/pi-admin/cleanup.sh
# Oder sudoers: pi ALL=(ALL) NOPASSWD: /home/pi/pi-admin/cleanup.sh
# =============================================================================

if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] Bitte mit sudo ausführen: sudo bash ~/pi-admin/cleanup.sh" >&2
    exit 1
fi

REAL_USER="${SUDO_USER:-pi}"
REAL_HOME=$(eval echo "~$REAL_USER")

source "$REAL_HOME/pi-admin/telegram_notify.sh"

LOG_FILE="$REAL_HOME/pi-admin/logs/cleanup.log"
mkdir -p "$REAL_HOME/pi-admin/logs"

BACKUP_DIR="${BACKUP_DIR:-$REAL_HOME/backup}"
BACKUP_MAX_AGE_DAYS="${BACKUP_MAX_AGE_DAYS:-30}"
LOG_MAX_AGE_DAYS="${LOG_MAX_AGE_DAYS:-60}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

get_disk_usage() {
    df -h / | awk 'NR==2 {print $5}' | tr -d '%'
}

log "====== Cleanup gestartet ======"
DISK_BEFORE=$(get_disk_usage)
DISK_FREE_BEFORE=$(df -h / | awk 'NR==2 {print $4}')
log "Disk vorher: ${DISK_BEFORE}% (${DISK_FREE_BEFORE} frei)"

# --- APT ---
log "APT-Cache bereinigen..."
APT_OUTPUT=$(apt-get autoclean 2>&1)
echo "$APT_OUTPUT" >> "$LOG_FILE"
APT_REMOVED=$(apt-get autoremove -y 2>&1)
echo "$APT_REMOVED" >> "$LOG_FILE"
APT_COUNT=$(echo "$APT_REMOVED" | grep -c "^Removing" || echo "0")

# --- Systemd-Logs ---
log "Systemd-Logs bereinigen..."
JOURNAL_BEFORE=$(journalctl --disk-usage 2>/dev/null | grep -oP '[\d.]+[KMGT]' | head -1)
journalctl --vacuum-size=100M 2>&1 >> "$LOG_FILE"
journalctl --vacuum-time=30d 2>&1 >> "$LOG_FILE"
JOURNAL_AFTER=$(journalctl --disk-usage 2>/dev/null | grep -oP '[\d.]+[KMGT]' | head -1)

# --- Tmp ---
log "Tmp-Dateien bereinigen..."
TMP_COUNT=$(find /tmp -type f -atime +7 2>/dev/null | wc -l)
find /tmp -type f -atime +7 -delete 2>/dev/null
find /var/tmp -type f -atime +14 -delete 2>/dev/null

# --- Script-Logs ---
log "Alte Script-Logs bereinigen (>${LOG_MAX_AGE_DAYS} Tage)..."
LOG_COUNT=$(find "$REAL_HOME/pi-admin/logs" -name "*.log" -mtime +"${LOG_MAX_AGE_DAYS}" 2>/dev/null | wc -l)
find "$REAL_HOME/pi-admin/logs" -name "*.log" -mtime +"${LOG_MAX_AGE_DAYS}" -delete 2>/dev/null

# --- Docker ---
log "Docker bereinigen..."
DOCKER_BEFORE=$(sudo -u "$REAL_USER" docker system df 2>/dev/null | awk 'NR>1 {sum+=$4} END {print sum}')
sudo -u "$REAL_USER" docker system prune -f 2>&1 >> "$LOG_FILE"
sudo -u "$REAL_USER" docker image prune -f 2>&1 >> "$LOG_FILE"
sudo -u "$REAL_USER" docker volume prune -f 2>&1 >> "$LOG_FILE"
DOCKER_RECLAIMED=$(sudo -u "$REAL_USER" docker system df 2>/dev/null | grep "Total" | awk '{print $4}')

# --- Alte Backups ---
log "Alte Backups bereinigen (>${BACKUP_MAX_AGE_DAYS} Tage)..."
DELETED_BACKUPS=0
DELETED_NAMES=""
if [ -d "$BACKUP_DIR" ]; then
    while IFS= read -r -d '' f; do
        DELETED_NAMES+="  • $(basename "$f")\n"
        rm -rf "$f"
        ((DELETED_BACKUPS++))
    done < <(find "$BACKUP_DIR" -maxdepth 2 \( -type d -o -name "*.tar.gz" \) \
             -mtime +"${BACKUP_MAX_AGE_DAYS}" -print0 2>/dev/null)
fi

DISK_AFTER=$(get_disk_usage)
DISK_FREE_AFTER=$(df -h / | awk 'NR==2 {print $4}')
FREED=$((DISK_BEFORE - DISK_AFTER))
log "Disk nachher: ${DISK_AFTER}% (${DISK_FREE_AFTER} frei)"
log "====== Cleanup beendet ======"

# --- Telegram ---
if [ "$FREED" -gt 5 ] || [ "$DISK_AFTER" -gt 80 ]; then

    WARN=""
    [ "$DISK_AFTER" -gt 80 ] && WARN="
⚠️ *Disk noch hoch – manuelle Prüfung empfohlen!*
  📋 \`df -h\` und \`du -sh ~/*\`
  🔧 \`docker system prune -af\`"

    BACKUP_MSG=""
    if [ "$DELETED_BACKUPS" -gt 0 ]; then
        BACKUP_MSG="
🗄️ *Alte Backups gelöscht (${DELETED_BACKUPS}):*
$(echo -e "$DELETED_NAMES")"
    fi

    send_telegram "*cleanup.sh – Bereinigung abgeschlossen* 🧹
━━━━━━━━━━━━━━━━━━━━
💽 *Disk:* ${DISK_BEFORE}% → ${DISK_AFTER}% (${FREED}% befreit)
  Vorher: ${DISK_FREE_BEFORE} frei → Nachher: ${DISK_FREE_AFTER} frei

📦 *APT:* ${APT_COUNT} Pakete entfernt
📋 *Logs:* ${LOG_COUNT} alte Logdateien gelöscht
  Journal: ${JOURNAL_BEFORE} → ${JOURNAL_AFTER}
🗑️ *Tmp:* ${TMP_COUNT} Dateien gelöscht
🐳 *Docker:* ${DOCKER_RECLAIMED} freigegeben
${BACKUP_MSG}${WARN}
━━━━━━━━━━━━━━━━━━━━
📄 Log: \`tail -30 ~/pi-admin/logs/cleanup.log\`" "🧹"
fi