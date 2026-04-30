#!/bin/bash
# =============================================================================
# telegram_notify.sh – Zentrale Benachrichtigungsfunktion via Telegram
# Aufruf: source ~/pi-admin/telegram_notify.sh
#         send_telegram "Deine Nachricht" [emoji]
# =============================================================================

# --- .env laden ---
ENV_FILE="$(dirname "${BASH_SOURCE[0]}")/.env"
if [ ! -f "$ENV_FILE" ]; then
    echo "[ERROR] .env nicht gefunden: $ENV_FILE" >&2
    exit 1
fi
set -a; source "$ENV_FILE"; set +a

# --- Pflichtfelder prüfen ---
if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ "$TELEGRAM_BOT_TOKEN" = "DEIN_BOT_TOKEN_HIER" ]; then
    echo "[ERROR] TELEGRAM_BOT_TOKEN nicht gesetzt in .env" >&2
    exit 1
fi
if [ -z "$TELEGRAM_CHAT_ID" ] || [ "$TELEGRAM_CHAT_ID" = "DEINE_CHAT_ID_HIER" ]; then
    echo "[ERROR] TELEGRAM_CHAT_ID nicht gesetzt in .env" >&2
    exit 1
fi

HOSTNAME=$(hostname)
PI_IP=$(hostname -I | awk '{print $1}')

# Sendet eine Nachricht via Telegram
# $1 = Nachrichtentext (Markdown erlaubt)
# $2 = optionales Emoji-Prefix (default: ℹ️)
send_telegram() {
    local message="$1"
    local emoji="${2:-ℹ️}"
    local timestamp
    timestamp=$(date '+%d.%m.%Y %H:%M')

    local full_message
    full_message="${emoji} *${HOSTNAME}* \`${PI_IP}\`
${message}
_${timestamp}_"

    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${full_message}" \
        --data-urlencode "parse_mode=Markdown" \
        > /dev/null 2>&1

    if [ $? -ne 0 ]; then
        echo "[WARN] Telegram-Nachricht konnte nicht gesendet werden." >&2
    fi
}

# Sendet eine Nachricht und wartet auf Bestätigung (mit Retry)
send_telegram_retry() {
    local message="$1"
    local emoji="${2:-ℹ️}"
    local retries=3

    for i in $(seq 1 $retries); do
        local response
        response=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
            --data-urlencode "text=${emoji} *${HOSTNAME}*: ${message}" \
            --data-urlencode "parse_mode=Markdown")

        if echo "$response" | grep -q '"ok":true'; then
            return 0
        fi
        sleep 5
    done

    echo "[ERROR] Telegram-Nachricht nach ${retries} Versuchen fehlgeschlagen." >&2
    return 1
}
