#!/bin/bash
# =============================================================================
# backup-home.sh – pi-home Konfigurationen sichern
# Sichert: Uptime Kuma, Syncthing, Nginx Proxy Manager
# Empfohlener Cron: 0 2 * * * /home/pi/pi-admin/backup-home.sh
# =============================================================================

source ~/pi-admin/telegram-notify.sh

LOG_FILE=~/pi-admin/logs/backup-home.log
mkdir -p ~/pi-admin/logs

BACKUP_BASE="${BACKUP_DIR:-$HOME/backup}"
BACKUP_TARGET="$BACKUP_BASE/pi-home"
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M')
BACKUP_NAME="pi-home_${TIMESTAMP}"
BACKUP_PATH="$BACKUP_TARGET/$BACKUP_NAME"
KEEP_DAYS="${BACKUP_MAX_AGE_DAYS:-30}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "====== pi-home Backup gestartet ======"
mkdir -p "$BACKUP_PATH"

BACKED_UP=()
FAILED=()

# --- Funktion: Stack sichern ---
backup_stack() {
    local stack="$1"
    local src="$HOME/docker/$stack"

    if [ ! -d "$src" ]; then
        log "  SKIP: $stack – Verzeichnis nicht gefunden"
        return
    fi

    log "  Sichere $stack..."

    # Container kurz stoppen für konsistentes Backup
    docker stop "$stack" 2>/dev/null
    cp -r "$src" "$BACKUP_PATH/$stack"
    docker start "$stack" 2>/dev/null

    if [ $? -eq 0 ]; then
        SIZE=$(du -sh "$BACKUP_PATH/$stack" | cut -f1)
        BACKED_UP+=("$stack ($SIZE)")
        log "  $stack gesichert ($SIZE)"
    else
        FAILED+=("$stack")
        log "  FEHLER: $stack"
    fi
}

# --- Stacks sichern ---
backup_stack "uptime-kuma"
backup_stack "syncthing"
backup_stack "nginx-proxy-manager"

# --- Komprimieren ---
log "Komprimieren..."
cd "$BACKUP_TARGET"
tar -czf "${BACKUP_NAME}.tar.gz" "$BACKUP_NAME" && rm -rf "$BACKUP_PATH"
BACKUP_SIZE=$(du -sh "${BACKUP_TARGET}/${BACKUP_NAME}.tar.gz" | cut -f1)
log "Backup erstellt: ${BACKUP_NAME}.tar.gz (${BACKUP_SIZE})"

# --- Alte Backups aufräumen ---
DELETED=0
while IFS= read -r -d '' f; do
    rm -f "$f"
    ((DELETED++))
done < <(find "$BACKUP_TARGET" -name "pi-home_*.tar.gz" -mtime +"$KEEP_DAYS" -print0 2>/dev/null)

BACKUP_COUNT=$(find "$BACKUP_TARGET" -name "pi-home_*.tar.gz" | wc -l)

log "====== Backup beendet ======"

# --- NAS Transfer (optional, gleiche Logik wie backup-adguard.sh) ---
NAS_ENABLED="${NAS_ENABLED:-false}"
NAS_MSG=""

if [ "$NAS_ENABLED" = "true" ]; then
    log "NAS-Transfer..."
    case "${NAS_METHOD:-rsync}" in
        rsync)
            rsync -az --timeout=30 \
                -e "ssh -i ${NAS_SSH_KEY:-~/.ssh/id_rsa_nas} -o StrictHostKeyChecking=no" \
                "${BACKUP_TARGET}/${BACKUP_NAME}.tar.gz" \
                "${NAS_USER}@${NAS_HOST}:${NAS_PATH}/" 2>&1 | tee -a "$LOG_FILE"
            [ ${PIPESTATUS[0]} -eq 0 ] \
                && NAS_MSG="
☁️ NAS-Transfer: ✅ ${NAS_HOST}" \
                || NAS_MSG="
☁️ NAS-Transfer: ❌ fehlgeschlagen"
            ;;
    esac
fi

# --- Telegram ---
BACKED_LIST=$(printf '  • %s\n' "${BACKED_UP[@]}")
FAILED_MSG=""
[ ${#FAILED[@]} -gt 0 ] && FAILED_MSG="
❌ *Fehlgeschlagen:*
$(printf '  • %s\n' "${FAILED[@]}")"

send_telegram "*backup-home.sh – Backup abgeschlossen* ✅
━━━━━━━━━━━━━━━━━━━━
💾 *Datei:* \`${BACKUP_NAME}.tar.gz\`
  Größe:    ${BACKUP_SIZE}
  Backups gesamt: ${BACKUP_COUNT}
  Gelöscht: ${DELETED} alte(s)

📦 *Gesicherte Stacks:*
${BACKED_LIST}
${FAILED_MSG}${NAS_MSG}
━━━━━━━━━━━━━━━━━━━━
📋 Prüfen: \`ls -lh ~/backup/pi-home/\`
📄 Log: \`tail -20 ~/pi-admin/logs/backup-home.log\`" "✅"