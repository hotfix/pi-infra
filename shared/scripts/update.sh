#!/bin/bash
# =============================================================================
# update.sh – Monatliche Systemupdates
# Empfohlener Cron: 0 3 1 * * /home/pi/pi-admin/update.sh
# =============================================================================

source ~/pi-admin/telegram_notify.sh

LOG_FILE=~/pi-admin/logs/update.log
mkdir -p ~/pi-admin/logs

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "====== Update gestartet ======"

# --- apt Update & Upgrade ---
log "Paketlisten werden aktualisiert..."
apt-get update -qq 2>&1 | tee -a "$LOG_FILE"

log "Pakete werden aktualisiert..."
UPGRADE_OUTPUT=$(DEBIAN_FRONTEND=noninteractive apt-get upgrade -y 2>&1)
echo "$UPGRADE_OUTPUT" >> "$LOG_FILE"
UPGRADE_EXIT=$?

# Aktualisierte Pakete auslesen
UPGRADED_PACKAGES=$(echo "$UPGRADE_OUTPUT" | grep "^Inst " | awk '{print "  • "$2}' | head -10)
UPGRADED_COUNT=$(echo "$UPGRADE_OUTPUT" | grep -c "^Inst " || echo "0")

# --- Autoremove ---
log "Autoremove..."
REMOVED_OUTPUT=$(apt-get autoremove -y 2>&1)
echo "$REMOVED_OUTPUT" >> "$LOG_FILE"
REMOVED_COUNT=$(echo "$REMOVED_OUTPUT" | grep -c "^Removing " || echo "0")
apt-get autoclean -qq 2>&1 >> "$LOG_FILE"

# --- Docker Images aktualisieren ---
log "Docker Images werden aktualisiert..."
UPDATED_IMAGES=()
FAILED_IMAGES=()

for image in $(docker ps --format '{{.Image}}' | sort -u); do
    log "  Pulling: $image"
    PULL_OUTPUT=$(docker pull "$image" 2>&1)
    if echo "$PULL_OUTPUT" | grep -q "newer\|Pull complete"; then
        UPDATED_IMAGES+=("$image")
    elif echo "$PULL_OUTPUT" | grep -q "Error\|error"; then
        FAILED_IMAGES+=("$image")
        log "  FEHLER beim Pull: $image"
    fi
done

# --- Container neu starten wenn Images aktualisiert ---
RESTARTED_STACKS=()
if [ ${#UPDATED_IMAGES[@]} -gt 0 ]; then
    log "Neue Images gefunden, starte betroffene Container neu..."
    DOCKER_BASE="${DOCKER_DIR:-$HOME/docker}"
    for dir in "$DOCKER_BASE"/*/; do
        if [ -f "${dir}compose.yml" ] || [ -f "${dir}docker-compose.yml" ]; then
            STACK=$(basename "$dir")
            cd "$dir" && docker compose pull -q && docker compose up -d 2>&1 | tee -a "$LOG_FILE"
            RESTARTED_STACKS+=("$STACK")
        fi
    done
fi

# --- Reboot prüfen ---
REBOOT_REQUIRED=false
REBOOT_REASON=""
if [ -f /var/run/reboot-required ]; then
    REBOOT_REQUIRED=true
    REBOOT_REASON=$(cat /var/run/reboot-required.pkgs 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
fi

# --- Disk nach Update ---
DISK_PERCENT=$(df / | awk 'NR==2 {printf "%.0f", $5}' | tr -d '%')
DISK_FREE=$(df -h / | awk 'NR==2 {print $4}')

log "====== Update beendet ======"

# --- Telegram Nachricht ---
if [ "$UPGRADE_EXIT" -eq 0 ]; then

    PACKAGES_MSG=""
    if [ "$UPGRADED_COUNT" -gt 0 ]; then
        PACKAGES_MSG="
📦 *Aktualisierte Pakete (${UPGRADED_COUNT}):*
${UPGRADED_PACKAGES}"
        [ "$UPGRADED_COUNT" -gt 10 ] && PACKAGES_MSG+="
  ... und $((UPGRADED_COUNT - 10)) weitere"
    else
        PACKAGES_MSG="
📦 Keine Pakete aktualisiert – System war bereits aktuell"
    fi

    REMOVED_MSG=""
    [ "$REMOVED_COUNT" -gt 0 ] && REMOVED_MSG="
🗑️ Entfernte Pakete: ${REMOVED_COUNT}"

    DOCKER_MSG=""
    if [ ${#UPDATED_IMAGES[@]} -gt 0 ]; then
        DOCKER_MSG="
🐳 *Docker Images aktualisiert:*
$(printf '  • %s\n' "${UPDATED_IMAGES[@]}")
  Neu gestartet: $(IFS=', '; echo "${RESTARTED_STACKS[*]}")"
    else
        DOCKER_MSG="
🐳 Docker Images: bereits aktuell"
    fi

    FAILED_MSG=""
    [ ${#FAILED_IMAGES[@]} -gt 0 ] && FAILED_MSG="
⚠️ Pull fehlgeschlagen: $(IFS=', '; echo "${FAILED_IMAGES[*]}")"

    REBOOT_MSG=""
    if $REBOOT_REQUIRED; then
        REBOOT_MSG="
━━━━━━━━━━━━━━━━━━━━
⚠️ *Reboot erforderlich!*
  Pakete: ${REBOOT_REASON}
  🔧 Ausführen: \`sudo reboot\`"
    fi

    send_telegram "*update.sh – Systemupdate abgeschlossen* ✅
━━━━━━━━━━━━━━━━━━━━
${PACKAGES_MSG}
${REMOVED_MSG}
${DOCKER_MSG}
${FAILED_MSG}
━━━━━━━━━━━━━━━━━━━━
💽 Disk nach Update: ${DISK_PERCENT}% (${DISK_FREE} frei)
📄 Log: \`tail -50 ~/pi-admin/logs/update.log\`${REBOOT_MSG}" "🔄"

else
    send_telegram "*update.sh – Update fehlgeschlagen* ❌
━━━━━━━━━━━━━━━━━━━━
Exit-Code: ${UPGRADE_EXIT}
━━━━━━━━━━━━━━━━━━━━
📋 *Prüfen:*
  \`tail -50 ~/pi-admin/logs/update.log\`
  \`sudo apt-get upgrade\`

🔧 *Mögliche Fixes:*
  \`sudo dpkg --configure -a\`
  \`sudo apt-get -f install\`" "🚨"
fi