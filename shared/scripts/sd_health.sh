#!/bin/bash
# =============================================================================
# sd_health.sh – SD-Karten Gesundheit prüfen (Pi 3B wichtig!)
# Empfohlener Cron: 0 6 * * 1 /home/pi/pi-admin/sd_health.sh  (Mo. morgens)
# =============================================================================

source ~/pi-admin/telegram_notify.sh

LOG_FILE=~/pi-admin/logs/sd_health.log
mkdir -p ~/pi-admin/logs

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "====== SD-Health-Check gestartet ======"

ISSUES=()

# --- Kernel I/O Fehler prüfen (zuverlässigster Indikator) ---
log "Kernel-Logs auf I/O-Fehler prüfen..."
IO_ERRORS=$(dmesg | grep -iE "mmc|sdcard|mmcblk" | grep -iE "error|failed|timeout|corruption|reset" | tail -20)
if [ -n "$IO_ERRORS" ]; then
    ERROR_COUNT=$(echo "$IO_ERRORS" | wc -l)
    ISSUES+=("🔴 ${ERROR_COUNT} I/O-Fehler im Kernel-Log gefunden")
    log "I/O-Fehler: $IO_ERRORS"
fi

# --- Filesystem Fehler (read-only mount = schlechtes Zeichen) ---
log "Filesystem-Status prüfen..."
if mount | grep "/ " | grep -q "ro,\|ro)"; then
    ISSUES+=("🔴 Root-Filesystem ist READ-ONLY (SD-Karte defekt?)")
    log "KRITISCH: Filesystem ist read-only!"
fi

# --- Bad Blocks (schneller Check, nicht destruktiv) ---
log "Bad Blocks prüfen (schnell)..."
SD_DEVICE=$(lsblk -ndo NAME /dev/mmcblk0 2>/dev/null | head -1)
if [ -n "$SD_DEVICE" ]; then
    BAD_BLOCKS=$(badblocks -n /dev/mmcblk0 -o /tmp/bb_check.txt 2>&1 | grep "Pass completed" | awk '{print $3}')
    if [ -f /tmp/bb_check.txt ] && [ -s /tmp/bb_check.txt ]; then
        BB_COUNT=$(wc -l < /tmp/bb_check.txt)
        ISSUES+=("🔴 ${BB_COUNT} Bad Block(s) gefunden!")
        log "Bad Blocks: $BB_COUNT"
    else
        log "Bad Blocks: keine gefunden"
    fi
    rm -f /tmp/bb_check.txt
fi

# --- Filesystem-Fehler aus Logs ---
log "Syslog auf FS-Fehler prüfen..."
FS_ERRORS=$(grep -iE "ext4_err|filesystem error|journal error|corruption" /var/log/syslog 2>/dev/null | tail -10)
if [ -n "$FS_ERRORS" ]; then
    FS_ERR_COUNT=$(echo "$FS_ERRORS" | wc -l)
    ISSUES+=("🟡 ${FS_ERR_COUNT} Filesystem-Fehler in syslog")
fi

# --- Disk-Auslastung (volle SD = Datenkorruption!) ---
log "Disk-Auslastung prüfen..."
DISK_PERCENT=$(df / | awk 'NR==2 {printf "%.0f", $5}' | tr -d '%')
DISK_FREE=$(df -h / | awk 'NR==2 {print $4}')
log "Disk: ${DISK_PERCENT}% belegt, ${DISK_FREE} frei"

[ "$DISK_PERCENT" -ge 90 ] && ISSUES+=("🟡 SD-Karte ${DISK_PERCENT}% voll (${DISK_FREE} frei)")

# --- Uptime & Temperatur (für Kontext) ---
UPTIME=$(uptime -p | sed 's/up //')
if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    TEMP=$(echo "scale=1; $(cat /sys/class/thermal/thermal_zone0/temp) / 1000" | bc)
else
    TEMP="unbekannt"
fi

log "====== SD-Health-Check beendet | Issues: ${#ISSUES[@]} ======"

# --- Benachrichtigung ---
if [ ${#ISSUES[@]} -gt 0 ]; then
    ISSUE_LIST=$(printf '%s\n' "${ISSUES[@]}")
    send_telegram "💾 *SD-Karten-Warnung!*
${ISSUE_LIST}

Disk: ${DISK_PERCENT}% | Temp: ${TEMP}°C
Uptime: ${UPTIME}

⚠️ Bitte zeitnah Backup erstellen!" "🚨"
else
    send_telegram "💾 *SD-Karte OK*
Keine Fehler gefunden
Disk: ${DISK_PERCENT}% belegt (${DISK_FREE} frei)
Uptime: ${UPTIME}" "✅"
fi