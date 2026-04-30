#!/bin/bash
# =============================================================================
# health_check.sh – Docker Container Statusprüfung
# Empfohlener Cron: */5 * * * * /home/pi/pi-admin/health_check.sh
# =============================================================================

source ~/pi-admin/telegram_notify.sh

LOG_FILE=~/pi-admin/logs/health_check.log
STATE_FILE=~/pi-admin/.health_state
mkdir -p ~/pi-admin/logs

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

UNHEALTHY=()
RECOVERED=()

# --- Container Details sammeln ---
get_container_details() {
    local name="$1"

    # Exit-Code
    EXIT_CODE=$(docker inspect --format='{{.State.ExitCode}}' "$name" 2>/dev/null)

    # Letzte Logzeile
    LAST_LOG=$(docker logs --tail 3 "$name" 2>&1 | tail -3 | sed 's/^/  /')

    # Lief seit wann
    STARTED=$(docker inspect --format='{{.State.StartedAt}}' "$name" 2>/dev/null | cut -dT -f1)

    # Image
    IMAGE=$(docker inspect --format='{{.Config.Image}}' "$name" 2>/dev/null)

    echo "Container: \`${name}\`
  Image:      ${IMAGE}
  Exit-Code:  ${EXIT_CODE}
  Zuletzt gestartet: ${STARTED}
  Letzte Logs:
${LAST_LOG}"
}

# --- Container prüfen ---
while IFS= read -r line; do
    CONTAINER=$(echo "$line" | awk '{print $NF}')
    STATUS=$(echo "$line" | awk '{print $1}')

    case "$STATUS" in
        "running"|"Up")
            if grep -q "^DOWN:${CONTAINER}$" "$STATE_FILE" 2>/dev/null; then
                RECOVERED+=("$CONTAINER")
                sed -i "/^DOWN:${CONTAINER}$/d" "$STATE_FILE"
                log "Erholt: $CONTAINER"
            fi
            ;;
        "exited"|"dead"|"removing"|"paused")
            if ! grep -q "^DOWN:${CONTAINER}$" "$STATE_FILE" 2>/dev/null; then
                echo "DOWN:${CONTAINER}" >> "$STATE_FILE"
                log "DOWN: $CONTAINER ($STATUS)"

                DETAILS=$(get_container_details "$CONTAINER")

                send_telegram "*health_check – Container ausgefallen*
━━━━━━━━━━━━━━━━━━━━
${DETAILS}
━━━━━━━━━━━━━━━━━━━━
📋 *Prüfen:*
  \`docker ps -a\`
  \`docker logs ${CONTAINER} --tail 20\`

🔧 *Neu starten:*
  \`cd ~/docker/${CONTAINER} && docker compose up -d\`

⚠️ *Falls Image-Problem:*
  \`docker compose pull && docker compose up -d\`" "🚨"
            fi
            ;;
    esac
done < <(docker ps -a --format "{{.State}} {{.Names}}" 2>/dev/null)

# --- Recovery-Nachricht ---
for container in "${RECOVERED[@]}"; do
    UPTIME=$(docker inspect --format='{{.State.StartedAt}}' "$container" 2>/dev/null | cut -dT -f1)
    IMAGE=$(docker inspect --format='{{.Config.Image}}' "$container" 2>/dev/null)

    send_telegram "*health_check – Container erholt* ✅
━━━━━━━━━━━━━━━━━━━━
Container: \`${container}\`
  Image:   ${IMAGE}
  Wieder online seit: ${UPTIME}
━━━━━━━━━━━━━━━━━━━━
📋 Status prüfen: \`docker ps | grep ${container}\`" "✅"
done

# --- DNS prüfen ---
DNS_RESPONSE=$(nslookup google.com 127.0.0.1 2>&1)
if ! echo "$DNS_RESPONSE" | grep -q "Address:"; then
    if ! grep -q "^DNS_DOWN$" "$STATE_FILE" 2>/dev/null; then
        echo "DNS_DOWN" >> "$STATE_FILE"

        # AdGuard Container-Status für mehr Kontext
        AG_STATUS=$(docker inspect --format='{{.State.Status}}' adguard 2>/dev/null || echo "nicht gefunden")
        AG_LOG=$(docker logs adguard --tail 3 2>&1 | sed 's/^/  /')

        send_telegram "*health_check – DNS ausgefallen*
━━━━━━━━━━━━━━━━━━━━
DNS 127.0.0.1 antwortet nicht
AdGuard Status: \`${AG_STATUS}\`
AdGuard Logs:
${AG_LOG}
━━━━━━━━━━━━━━━━━━━━
📋 *Prüfen:*
  \`nslookup google.com 127.0.0.1\`
  \`docker ps | grep adguard\`
  \`docker logs adguard --tail 20\`

🔧 *Neu starten:*
  \`cd ~/docker/adguard && docker compose restart\`" "🚨"
        log "ALERT: DNS ausgefallen – AdGuard: ${AG_STATUS}"
    fi
else
    # DNS wieder ok
    if grep -q "^DNS_DOWN$" "$STATE_FILE" 2>/dev/null; then
        sed -i "/^DNS_DOWN$/d" "$STATE_FILE"
        send_telegram "*health_check – DNS wieder erreichbar* ✅
━━━━━━━━━━━━━━━━━━━━
DNS 127.0.0.1 antwortet wieder
📋 Prüfen: \`nslookup google.com 127.0.0.1\`" "✅"
        log "DNS wieder erreichbar"
    fi
fi

log "Health-Check OK | Unhealthy: ${#UNHEALTHY[@]} | Recovered: ${#RECOVERED[@]}"