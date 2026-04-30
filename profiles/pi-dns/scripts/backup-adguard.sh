#!/bin/bash
# =============================================================================
# backup_adguard.sh – AdGuard Home Konfiguration sichern
# Empfohlener Cron: 0 2 * * * /home/pi/pi-admin/backup_adguard.sh
#
# Was wird gesichert:
#   ~/docker/adguard/conf/  – Einstellungen, Filter, DNS-Regeln
#   ~/docker/adguard/data/  – Statistiken, Query-Log
#
# NAS-Transfer: In .env aktivieren (NAS_ENABLED=true)
# =============================================================================

source ~/pi-admin/telegram_notify.sh

LOG_FILE=~/pi-admin/logs/backup_adguard.log
mkdir -p ~/pi-admin/logs

BACKUP_BASE="${BACKUP_DIR:-$HOME/backup}"
BACKUP_TARGET="$BACKUP_BASE/adguard"
ADGUARD_CONF="${ADGUARD_CONF_DIR:-$HOME/docker/adguard/conf}"
ADGUARD_DATA="${ADGUARD_DATA_DIR:-$HOME/docker/adguard/data}"
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M')
BACKUP_NAME="adguard_${TIMESTAMP}"
BACKUP_PATH="$BACKUP_TARGET/$BACKUP_NAME"
KEEP_DAYS="${BACKUP_MAX_AGE_DAYS:-30}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "====== AdGuard Backup gestartet ======"

# --- Verzeichnisse prüfen ---
if [ ! -d "$ADGUARD_CONF" ] && [ ! -d "$ADGUARD_DATA" ]; then
    log "ERROR: AdGuard Verzeichnisse nicht gefunden: $ADGUARD_CONF"
    send_telegram "❌ *Backup fehlgeschlagen!*
AdGuard Verzeichnis nicht gefunden.
Läuft AdGuard? \`docker ps | grep adguard\`" "🚨"
    exit 1
fi

mkdir -p "$BACKUP_PATH"

# --- AdGuard stoppen für konsistentes Backup ---
log "AdGuard wird kurz gestoppt..."
docker stop adguard 2>/dev/null && ADGUARD_WAS_RUNNING=true || ADGUARD_WAS_RUNNING=false

# --- Dateien sichern ---
log "Konfiguration sichern: $ADGUARD_CONF"
if [ -d "$ADGUARD_CONF" ]; then
    cp -r "$ADGUARD_CONF" "$BACKUP_PATH/conf"
    log "  conf/ gesichert ($(du -sh "$BACKUP_PATH/conf" | cut -f1))"
fi

log "Daten sichern: $ADGUARD_DATA"
if [ -d "$ADGUARD_DATA" ]; then
    # Query-Log kann sehr groß werden – nur letzte 7 Tage
    mkdir -p "$BACKUP_PATH/data"
    find "$ADGUARD_DATA" -name "*.yaml" -o -name "*.db" | while read -r f; do
        cp "$f" "$BACKUP_PATH/data/"
    done
    log "  data/ gesichert ($(du -sh "$BACKUP_PATH/data" | cut -f1))"
fi

# --- AdGuard wieder starten ---
if $ADGUARD_WAS_RUNNING; then
    docker start adguard 2>/dev/null
    log "AdGuard wieder gestartet"
fi

# --- Backup komprimieren ---
log "Komprimieren..."
cd "$BACKUP_TARGET"
tar -czf "${BACKUP_NAME}.tar.gz" "$BACKUP_NAME" && rm -rf "$BACKUP_PATH"
BACKUP_SIZE=$(du -sh "${BACKUP_TARGET}/${BACKUP_NAME}.tar.gz" | cut -f1)
log "Backup erstellt: ${BACKUP_NAME}.tar.gz (${BACKUP_SIZE})"

# --- Alte Backups aufräumen ---
log "Alte Backups bereinigen (älter als ${KEEP_DAYS} Tage)..."
DELETED=0
while IFS= read -r -d '' f; do
    rm -f "$f"
    log "  Gelöscht: $(basename "$f")"
    ((DELETED++))
done < <(find "$BACKUP_TARGET" -name "adguard_*.tar.gz" -mtime +"$KEEP_DAYS" -print0 2>/dev/null)

BACKUP_COUNT=$(find "$BACKUP_TARGET" -name "adguard_*.tar.gz" | wc -l)

# =============================================================================
# NAS-Transfer (aktivieren in ~/pi-admin/.env):
#   NAS_ENABLED=true
#   NAS_METHOD=rsync        # oder: smb
#
# --- rsync über SSH ---
#   NAS_HOST=192.168.1.100
#   NAS_USER=admin
#   NAS_PATH=/share/backup/pi-dns
#   NAS_SSH_KEY=~/.ssh/id_rsa_nas
#
# --- SMB/Samba ---
#   NAS_HOST=192.168.1.100
#   NAS_SHARE=backup
#   NAS_SMB_USER=admin
#   NAS_SMB_PASS=geheim       # Alternativ in ~/.smbcredentials
#   NAS_PATH=/pi-dns
# =============================================================================

NAS_ENABLED="${NAS_ENABLED:-false}"

if [ "$NAS_ENABLED" = "true" ]; then
    log "NAS-Transfer wird gestartet (Methode: ${NAS_METHOD:-rsync})..."

    NAS_SUCCESS=false

    case "${NAS_METHOD:-rsync}" in

        rsync)
            NAS_HOST="${NAS_HOST:?NAS_HOST nicht gesetzt in .env}"
            NAS_USER="${NAS_USER:?NAS_USER nicht gesetzt in .env}"
            NAS_PATH="${NAS_PATH:?NAS_PATH nicht gesetzt in .env}"
            NAS_SSH_KEY="${NAS_SSH_KEY:-~/.ssh/id_rsa_nas}"

            rsync -az --timeout=30 \
                -e "ssh -i $NAS_SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10" \
                "${BACKUP_TARGET}/${BACKUP_NAME}.tar.gz" \
                "${NAS_USER}@${NAS_HOST}:${NAS_PATH}/" \
                2>&1 | tee -a "$LOG_FILE"

            [ ${PIPESTATUS[0]} -eq 0 ] && NAS_SUCCESS=true
            ;;

        smb)
            NAS_HOST="${NAS_HOST:?NAS_HOST nicht gesetzt in .env}"
            NAS_SHARE="${NAS_SHARE:?NAS_SHARE nicht gesetzt in .env}"
            NAS_PATH="${NAS_PATH:-/}"

            # Credentials aus Datei oder .env
            if [ -f ~/.smbcredentials ]; then
                CREDS="credentials=$HOME/.smbcredentials"
            else
                NAS_SMB_USER="${NAS_SMB_USER:?NAS_SMB_USER nicht gesetzt}"
                NAS_SMB_PASS="${NAS_SMB_PASS:?NAS_SMB_PASS nicht gesetzt}"
                CREDS="username=$NAS_SMB_USER,password=$NAS_SMB_PASS"
            fi

            MOUNT_POINT="/tmp/nas_backup_$$"
            mkdir -p "$MOUNT_POINT"

            if mount -t cifs "//${NAS_HOST}/${NAS_SHARE}" "$MOUNT_POINT" \
                -o "$CREDS,uid=$(id -u),gid=$(id -g)" 2>&1 | tee -a "$LOG_FILE"; then

                mkdir -p "${MOUNT_POINT}${NAS_PATH}"
                cp "${BACKUP_TARGET}/${BACKUP_NAME}.tar.gz" "${MOUNT_POINT}${NAS_PATH}/"
                [ $? -eq 0 ] && NAS_SUCCESS=true
                umount "$MOUNT_POINT"
            fi
            rm -rf "$MOUNT_POINT"
            ;;

        *)
            log "WARN: Unbekannte NAS_METHOD: ${NAS_METHOD}"
            ;;
    esac

    if $NAS_SUCCESS; then
        log "NAS-Transfer erfolgreich"
        NAS_MSG="
☁️ NAS-Transfer: ✅ ${NAS_HOST}"
    else
        log "ERROR: NAS-Transfer fehlgeschlagen"
        NAS_MSG="
☁️ NAS-Transfer: ❌ fehlgeschlagen"
        send_telegram "⚠️ *NAS-Transfer fehlgeschlagen!*
Backup lokal gespeichert: \`${BACKUP_NAME}.tar.gz\`
Bitte NAS-Verbindung prüfen." "⚠️"
    fi
else
    NAS_MSG=""
fi

log "====== Backup beendet ======"

send_telegram "*backup_adguard.sh – Backup abgeschlossen* ✅
━━━━━━━━━━━━━━━━━━━━
Datei: \`${BACKUP_NAME}.tar.gz\` (${BACKUP_SIZE})
Lokal gespeichert: ${BACKUP_COUNT} Backup(s)
Gelöscht: ${DELETED} alte(s)${NAS_MSG}" "✅"