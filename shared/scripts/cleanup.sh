#!/bin/bash
# =============================================================================
# cleanup.sh – Speicher & Logs bereinigen
# Empfohlener Cron: 0 4 * * 0 /home/pi/pi-admin/cleanup.sh  (wöchentlich So.)
# =============================================================================

source ~/pi-admin/telegram_notify.sh

LOG_FILE=~/pi-admin/logs/cleanup.log
mkdir -p ~/pi-admin/logs

BACKUP_DIR="${BACKUP_DIR:-$HOME/backup}"
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
log "Disk-Auslastung vorher: ${DISK_BEFORE}%"

# --- apt Cache bereinigen ---
log "APT-Cache bereinigen..."
apt-get autoclean -qq 2>&1 | tee -a "$LOG_FILE"
apt-get autoremove -y -qq 2>&1 | tee -a "$LOG_FILE"

# --- Systemd-Logs auf 100 MB begrenzen ---
log "Systemd-Logs bereinigen..."
journalctl --vacuum-size=100M 2>&1 | tee -a "$LOG_FILE"
journalctl --vacuum-time=30d 2>&1 | tee -a "$LOG_FILE"

# --- Tmp-Dateien bereinigen ---
log "Tmp-Dateien bereinigen..."
find /tmp -type f -atime +7 -delete 2>/dev/null
find /var/tmp -type f -atime +14 -delete 2>/dev/null

# --- Alte pi-admin Logs bereinigen (>60 Tage) ---
log "Alte Script-Logs bereinigen..."
find ~/pi-admin/logs -name "*.log" -mtime +${LOG_MAX_AGE_DAYS} -delete 2>/dev/null

# --- Docker Cleanup ---
log "Docker bereinigen..."
DOCKER_BEFORE=$(docker system df 2>/dev/null | grep "Total Space" | awk '{print $3}' || echo "unbekannt")

docker system prune -f 2>&1 | tee -a "$LOG_FILE"         # Gestoppte Container, Netzwerke
docker image prune -f 2>&1 | tee -a "$LOG_FILE"           # Nicht getaggte Images
docker volume prune -f 2>&1 | tee -a "$LOG_FILE"          # Ungenutzte Volumes

DOCKER_AFTER=$(docker system df 2>/dev/null | grep "Total Space" | awk '{print $3}' || echo "unbekannt")

# --- Alte Backups löschen ---
log "Alte Backups bereinigen (älter als ${BACKUP_MAX_AGE_DAYS} Tage)..."
DELETED_BACKUPS=0
if [ -d "$BACKUP_DIR" ]; then
    while IFS= read -r -d '' dir; do
        rm -rf "$dir"
        log "  Gelöscht: $dir"
        ((DELETED_BACKUPS++))
    done < <(find "$BACKUP_DIR" -maxdepth 2 -type d -mtime +${BACKUP_MAX_AGE_DAYS} -print0 2>/dev/null)
fi

DISK_AFTER=$(get_disk_usage)
log "Disk-Auslastung nachher: ${DISK_AFTER}%"
FREED=$((DISK_BEFORE - DISK_AFTER))

log "====== Cleanup beendet ======"

# Nur benachrichtigen wenn >5% Disk gespart oder Disk >80% voll
if [ "$FREED" -gt 5 ] || [ "$DISK_AFTER" -gt 80 ]; then
    WARN=""
    [ "$DISK_AFTER" -gt 80 ] && WARN="
⚠️ Disk-Auslastung noch hoch!"

    send_telegram "🧹 *Cleanup abgeschlossen*
Disk: ${DISK_BEFORE}% → ${DISK_AFTER}% (${FREED}% befreit)
Backups gelöscht: ${DELETED_BACKUPS}${WARN}" "🧹"
fi
