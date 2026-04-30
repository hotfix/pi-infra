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
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y 2>&1 | tee -a "$LOG_FILE"
UPGRADE_EXIT=$?

# --- Nicht mehr benötigte Pakete entfernen ---
log "Autoremove..."
apt-get autoremove -y -qq 2>&1 | tee -a "$LOG_FILE"
apt-get autoclean -qq 2>&1 | tee -a "$LOG_FILE"

# --- Docker Images aktualisieren ---
log "Docker Images werden aktualisiert..."
UPDATED_IMAGES=()
for image in $(docker ps --format '{{.Image}}' | sort -u); do
    log "  Pulling: $image"
    if docker pull "$image" 2>&1 | grep -q "newer"; then
        UPDATED_IMAGES+=("$image")
    fi
done

# --- Docker Container neu starten wenn Images aktualisiert ---
if [ ${#UPDATED_IMAGES[@]} -gt 0 ]; then
    log "Neue Images gefunden, starte betroffene Container neu..."
    DOCKER_BASE="${DOCKER_DIR:-$HOME/docker}"
    for dir in "$DOCKER_BASE"/*/; do
        if [ -f "${dir}compose.yml" ] || [ -f "${dir}docker-compose.yml" ]; then
        cd "$dir" && docker compose pull && docker compose up -d 2>&1 | tee -a "$LOG_FILE"
        fi
    done
fi

# --- Reboot prüfen ---
REBOOT_REQUIRED=false
if [ -f /var/run/reboot-required ]; then
    REBOOT_REQUIRED=true
    log "Reboot erforderlich!"
fi

# --- Zusammenfassung ---
UPDATED_COUNT=$(grep -c "upgraded" "$LOG_FILE" 2>/dev/null || echo "0")
DOCKER_MSG=""
if [ ${#UPDATED_IMAGES[@]} -gt 0 ]; then
    DOCKER_MSG="
🐳 Docker aktualisiert: $(IFS=', '; echo "${UPDATED_IMAGES[*]}")"
fi

REBOOT_MSG=""
if $REBOOT_REQUIRED; then
    REBOOT_MSG="
⚠️ Reboot empfohlen"
fi

if [ $UPGRADE_EXIT -eq 0 ]; then
    send_telegram "✅ *Systemupdate abgeschlossen*
Pakete aktualisiert${DOCKER_MSG}${REBOOT_MSG}" "🔄"
else
    send_telegram "❌ *Update fehlgeschlagen!*
Bitte Log prüfen: \`${LOG_FILE}\`" "🚨"
fi

log "====== Update beendet ======"
