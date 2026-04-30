#!/bin/bash
# =============================================================================
# health_check.sh – Docker Container Statusprüfung
# Empfohlener Cron: */5 * * * * /home/pi/pi-admin/health_check.sh
# =============================================================================

source ~/pi-admin/telegram_notify.sh

LOG_FILE=~/pi-admin/logs/health_check.log
STATE_FILE=~/pi-admin/.health_state   # Merkt sich bekannte Zustände
mkdir -p ~/pi-admin/logs

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# --- Container prüfen ---
UNHEALTHY=()
RECOVERED=()

while IFS= read -r line; do
    CONTAINER=$(echo "$line" | awk '{print $NF}')
    STATUS=$(echo "$line" | awk '{print $2}')

    case "$STATUS" in
        "running"|"Up")
            # Vorher als down bekannt? → Recovery-Alert
            if grep -q "^DOWN:${CONTAINER}$" "$STATE_FILE" 2>/dev/null; then
                RECOVERED+=("$CONTAINER")
                sed -i "/^DOWN:${CONTAINER}$/d" "$STATE_FILE"
                log "Erholt: $CONTAINER"
            fi
            ;;
        "exited"|"dead"|"removing"|"paused")
            UNHEALTHY+=("$CONTAINER ($STATUS)")
            # Nur einmal warnen (nicht bei jedem Cron-Lauf)
            if ! grep -q "^DOWN:${CONTAINER}$" "$STATE_FILE" 2>/dev/null; then
                echo "DOWN:${CONTAINER}" >> "$STATE_FILE"
                log "DOWN: $CONTAINER ($STATUS)"
            fi
            ;;
    esac
done < <(docker ps -a --format "{{.Status}} {{.Names}}" 2>/dev/null)

# --- Benachrichtigungen ---
if [ ${#UNHEALTHY[@]} -gt 0 ]; then
    UNHEALTHY_LIST=$(printf '❌ %s\n' "${UNHEALTHY[@]}")
    send_telegram "🐳 *Container ausgefallen!*
${UNHEALTHY_LIST}

Prüfen mit: \`docker ps -a\`
Neustart: \`docker compose up -d\`" "🚨"
fi

if [ ${#RECOVERED[@]} -gt 0 ]; then
    RECOVERED_LIST=$(printf '✅ %s\n' "${RECOVERED[@]}")
    send_telegram "🐳 *Container erholt!*
${RECOVERED_LIST}" "✅"
fi

# --- AdGuard DNS prüfen (Pi-spezifisch) ---
if ! nslookup google.com 127.0.0.1 > /dev/null 2>&1; then
    STATE_KEY="DNS_DOWN"
    if ! grep -q "^${STATE_KEY}$" "$STATE_FILE" 2>/dev/null; then
        echo "$STATE_KEY" >> "$STATE_FILE"
        send_telegram "⚠️ *DNS nicht erreichbar!*
AdGuard antwortet nicht auf 127.0.0.1
Pi läuft als DNS-Server – bitte prüfen!" "🚨"
        log "ALERT: DNS ausgefallen"
    fi
else
    sed -i "/^DNS_DOWN$/d" "$STATE_FILE" 2>/dev/null
fi

log "Health-Check OK | Unhealthy: ${#UNHEALTHY[@]} | Recovered: ${#RECOVERED[@]}"