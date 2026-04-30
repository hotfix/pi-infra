#!/bin/bash
# =============================================================================
# sd_health.sh – SD-Karten Gesundheit prüfen (Pi 3B wichtig!)
# Empfohlener Cron: 0 6 * * 1 /home/pi/pi-admin/sd_health.sh
# =============================================================================

source ~/pi-admin/telegram_notify.sh

LOG_FILE=~/pi-admin/logs/sd_health.log
mkdir -p ~/pi-admin/logs

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "====== SD-Health-Check gestartet ======"

ISSUES=()
INFOS=()

# --- I/O Fehler im Kernel-Log ---
log "Kernel-Logs auf I/O-Fehler prüfen..."
IO_ERRORS=$(dmesg | grep -iE "mmc|sdcard|mmcblk" | grep -iE "error|failed|timeout|corruption|reset" | tail -5)
IO_COUNT=0
if [ -n "$IO_ERRORS" ]; then
    IO_COUNT=$(echo "$IO_ERRORS" | wc -l)
    ISSUES+=("io_errors")
    log "I/O-Fehler gefunden: $IO_COUNT"
else
    INFOS+=("✅ Keine I/O-Fehler im Kernel-Log")
    log "Keine I/O-Fehler"
fi

# --- Filesystem Read-Only ---
log "Filesystem-Status prüfen..."
if mount | grep "/ " | grep -q "ro,\|ro)"; then
    ISSUES+=("readonly")
    log "KRITISCH: Filesystem ist read-only"
else
    INFOS+=("✅ Filesystem read/write – normal")
fi

# --- Bad Blocks ---
log "Bad Blocks prüfen..."
BAD_BLOCK_COUNT=0
if command -v badblocks &>/dev/null; then
    badblocks -n /dev/mmcblk0 -o /tmp/bb_check.txt 2>/dev/null
    if [ -f /tmp/bb_check.txt ] && [ -s /tmp/bb_check.txt ]; then
        BAD_BLOCK_COUNT=$(wc -l < /tmp/bb_check.txt)
        ISSUES+=("bad_blocks")
        log "Bad Blocks: $BAD_BLOCK_COUNT"
    else
        INFOS+=("✅ Keine Bad Blocks gefunden")
        log "Keine Bad Blocks"
    fi
    rm -f /tmp/bb_check.txt
fi

# --- Filesystem-Fehler in syslog ---
log "Syslog auf FS-Fehler prüfen..."
FS_ERRORS=$(grep -iE "ext4_err|filesystem error|journal error|corruption" /var/log/syslog 2>/dev/null | tail -3)
FS_COUNT=0
if [ -n "$FS_ERRORS" ]; then
    FS_COUNT=$(echo "$FS_ERRORS" | wc -l)
    ISSUES+=("fs_errors")
    log "FS-Fehler in syslog: $FS_COUNT"
else
    INFOS+=("✅ Keine Filesystem-Fehler in syslog")
fi

# --- Disk-Auslastung ---
DISK_PERCENT=$(df / | awk 'NR==2 {printf "%.0f", $5}' | tr -d '%')
DISK_FREE=$(df -h / | awk 'NR==2 {print $4}')
DISK_USED=$(df -h / | awk 'NR==2 {print $3}')
DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
log "Disk: ${DISK_PERCENT}% belegt (${DISK_USED}/${DISK_TOTAL}, ${DISK_FREE} frei)"

if [ "$DISK_PERCENT" -ge 90 ]; then
    ISSUES+=("disk_full")
elif [ "$DISK_PERCENT" -ge 75 ]; then
    INFOS+=("⚠️ Disk ${DISK_PERCENT}% belegt – im Auge behalten")
else
    INFOS+=("✅ Disk ${DISK_PERCENT}% belegt (${DISK_FREE} frei)")
fi

# --- Systeminfo ---
UPTIME=$(uptime -p | sed 's/up //')
TEMP=$(echo "scale=1; $(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0) / 1000" | bc)
KERNEL=$(uname -r)

log "====== SD-Health-Check beendet | Issues: ${#ISSUES[@]} ======"

# --- Telegram Nachricht ---
INFO_LIST=$(printf '%s\n' "${INFOS[@]}")

if [ ${#ISSUES[@]} -gt 0 ]; then

    ISSUE_DETAILS=""

    for issue in "${ISSUES[@]}"; do
        case "$issue" in
            io_errors)
                LAST_ERRORS=$(echo "$IO_ERRORS" | tail -3 | sed 's/^/  /')
                ISSUE_DETAILS+="
🔴 *I/O-Fehler (${IO_COUNT}x im Kernel-Log)*
${LAST_ERRORS}
  📋 Prüfen:  \`dmesg | grep -i mmc | tail -20\`
  🔧 Sofort Backup erstellen!"
                ;;
            readonly)
                ISSUE_DETAILS+="
🔴 *Filesystem ist READ-ONLY!*
  Das bedeutet die SD-Karte ist sehr wahrscheinlich defekt.
  📋 Prüfen:  \`mount | grep ' / '\`
  🔧 Fixen:   \`sudo fsck /dev/mmcblk0p2\` (nur unmounted!)
  ⚠️ Sofort neue SD-Karte besorgen und Backup einspielen!"
                ;;
            bad_blocks)
                ISSUE_DETAILS+="
🔴 *Bad Blocks gefunden (${BAD_BLOCK_COUNT})*
  Defekte Sektoren auf der SD-Karte – Datenverlust möglich!
  📋 Prüfen:  \`badblocks -v /dev/mmcblk0\`
  🔧 Neue SD-Karte besorgen, Backup einspielen"
                ;;
            fs_errors)
                LAST_FS=$(echo "$FS_ERRORS" | tail -2 | sed 's/^/  /')
                ISSUE_DETAILS+="
🟡 *Filesystem-Fehler in syslog (${FS_COUNT}x)*
${LAST_FS}
  📋 Prüfen:  \`grep -i 'filesystem error' /var/log/syslog | tail -10\`
  🔧 Fixen:   \`sudo fsck -y /dev/mmcblk0p2\` (nur unmounted!)"
                ;;
            disk_full)
                ISSUE_DETAILS+="
🟡 *SD-Karte fast voll (${DISK_PERCENT}%)*
  Nur noch ${DISK_FREE} von ${DISK_TOTAL} frei – Gefahr der Datenkorruption!
  📋 Prüfen:  \`df -h\` und \`du -sh ~/*\`
  🔧 Fixen:   \`sudo bash ~/pi-admin/cleanup.sh\`"
                ;;
        esac
    done

    send_telegram "*sd_health.sh – SD-Karten Warnung!* ⚠️
━━━━━━━━━━━━━━━━━━━━
${ISSUE_DETAILS}
━━━━━━━━━━━━━━━━━━━━
*Systeminfo:*
  Uptime:       ${UPTIME}
  Temperatur:   ${TEMP}°C
  Kernel:       ${KERNEL}
  Disk:         ${DISK_PERCENT}% (${DISK_FREE} frei)

💾 Backup empfohlen: \`bash ~/pi-admin/backup_adguard.sh\`
📄 Log: \`tail -30 ~/pi-admin/logs/sd_health.log\`" "🚨"

else
    send_telegram "*sd_health.sh – SD-Karte OK* ✅
━━━━━━━━━━━━━━━━━━━━
${INFO_LIST}
━━━━━━━━━━━━━━━━━━━━
*Systeminfo:*
  Uptime:       ${UPTIME}
  Temperatur:   ${TEMP}°C
  Kernel:       ${KERNEL}
  Disk:         ${DISK_PERCENT}% (${DISK_FREE} frei)
━━━━━━━━━━━━━━━━━━━━
📄 Log: \`tail -20 ~/pi-admin/logs/sd_health.log\`" "💾"
fi