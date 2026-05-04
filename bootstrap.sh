#!/bin/bash
# =============================================================================
# bootstrap.sh – Pi Infrastruktur Einstiegspunkt
#
# Aufruf (frischer Pi):
#   curl -s https://codeberg.org/hotfix/pi-infra/raw/branch/main/bootstrap.sh | sudo bash
#
# Mit Profil direkt:
#   curl -s https://codeberg.org/hotfix/pi-infra/raw/branch/main/bootstrap.sh | sudo bash -s pi-home
#
# Repo bereits vorhanden:
#   sudo bash ~/pi-infra/bootstrap.sh [profil]
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step()    { echo -e "\n${BOLD}──────────────────────────────${NC}"; echo -e "${BOLD} $*${NC}"; echo -e "${BOLD}──────────────────────────────${NC}"; }

# --- Root prüfen ---
if [ "$EUID" -ne 0 ]; then
    error "Bitte als root ausführen: curl -s URL | sudo bash"
fi

# --- Echten Benutzer ermitteln (nicht root) ---
REAL_USER="${SUDO_USER:-pi}"
REAL_HOME=$(eval echo "~$REAL_USER")

# INSTALL_DIR zeigt auf Home des echten Benutzers – nicht /root
INSTALL_DIR="$REAL_HOME/pi-infra"
SHARED_DIR="$INSTALL_DIR/shared"

echo ""
echo -e "${BOLD}  Pi Infrastruktur Bootstrap${NC}"
echo -e "  Benutzer: ${REAL_USER} | Home: ${REAL_HOME} | Host: $(hostname)"
echo ""

# =============================================================================
# REPO-URL ermitteln
# Priorität: 1) Bereits geclontes Repo  2) Env-Variable  3) Interaktiv
# =============================================================================
step "Repo einrichten"

REPO_URL=""

# Bereits geclont?
if [ -d "$INSTALL_DIR/.git" ]; then
    REPO_URL=$(sudo -u "$REAL_USER" git -C "$INSTALL_DIR" remote get-url origin 2>/dev/null || echo "")
fi

# Env-Variable gesetzt? (nützlich für deploy.ps1)
if [ -z "$REPO_URL" ]; then
    REPO_URL="${PI_INFRA_REPO:-}"
fi

# Interaktiv abfragen
if [ -z "$REPO_URL" ]; then
    echo ""
    info "Codeberg Benutzername oder vollständige URL eingeben."
    info "  Nur Username:  hotfix"
    info "  Volle URL:     https://codeberg.org/hotfix/pi-infra"
    echo ""
    read -rp "  Codeberg Username oder URL: " REPO_INPUT
    [ -z "$REPO_INPUT" ] && error "Eingabe ist pflicht."

    # Nur Username eingegeben → URL automatisch vervollständigen
    if [[ "$REPO_INPUT" != http* ]]; then
        REPO_URL="https://codeberg.org/${REPO_INPUT}/pi-infra"
        info "URL vervollständigt: $REPO_URL"
    else
        REPO_URL="$REPO_INPUT"
    fi
fi

# Platzhalter abfangen
[[ "$REPO_URL" == *"DEIN_USER"* ]] && error "Bitte echten Codeberg-Username eingeben."

info "Repo: $REPO_URL"
info "Ziel: $INSTALL_DIR"

# Clonen oder aktualisieren
if [ ! -d "$INSTALL_DIR/.git" ]; then
    info "Cloning..."
    sudo -u "$REAL_USER" git clone "$REPO_URL" "$INSTALL_DIR" \
        || error "Clone fehlgeschlagen – URL korrekt? Netzwerk ok?"
    success "Repo geclont nach $INSTALL_DIR"
else
    info "Repo bereits vorhanden, aktualisiere..."
    sudo -u "$REAL_USER" git -C "$INSTALL_DIR" pull --ff-only
    success "Repo aktualisiert"
fi

# =============================================================================
# PROFIL wählen
# =============================================================================
step "Profil wählen"

PROFILES=()
for dir in "$INSTALL_DIR/profiles"/*/; do
    [ -f "${dir}profile.sh" ] && PROFILES+=("$(basename "$dir")")
done

[ ${#PROFILES[@]} -eq 0 ] && error "Keine Profile gefunden in $INSTALL_DIR/profiles/"

CHOSEN_PROFILE="${1:-}"
if [ -z "$CHOSEN_PROFILE" ]; then
    echo "Verfügbare Profile:"
    for i in "${!PROFILES[@]}"; do
        PROFILE="${PROFILES[$i]}"
        DESC=$(grep "^PROFILE_DESC=" "$INSTALL_DIR/profiles/$PROFILE/profile.sh" 2>/dev/null | cut -d'"' -f2 || echo "")
        echo "  $((i+1))) $PROFILE  – $DESC"
    done
    echo ""
    read -rp "Profil wählen [1-${#PROFILES[@]}]: " CHOICE
    CHOSEN_PROFILE="${PROFILES[$((CHOICE-1))]}"
fi

PROFILE_DIR="$INSTALL_DIR/profiles/$CHOSEN_PROFILE"
[ -f "$PROFILE_DIR/profile.sh" ] || error "Profil nicht gefunden: $CHOSEN_PROFILE"
success "Gewähltes Profil: $CHOSEN_PROFILE"

# =============================================================================
# MODUS wählen
# =============================================================================
step "Modus wählen"

CHOSEN_MODE="${2:-}"
if [ -z "$CHOSEN_MODE" ]; then
    echo ""
    echo "  Wie soll das Profil eingerichtet werden?"
    echo ""
    echo "  1) Neu-Installation  – alles frisch einrichten"
    echo "  2) Stack hinzufügen  – neuen Container auf bestehendem Pi"
    echo "  3) Aktualisieren     – Scripts + Images updaten, Container neu starten"
    echo "  4) Reset             – alle Container neu aufbauen, Daten bleiben erhalten"
    echo ""
    read -rp "  Modus wählen [1-4]: " MODE_CHOICE
    case "$MODE_CHOICE" in
        1) CHOSEN_MODE="fresh" ;;
        2) CHOSEN_MODE="add" ;;
        3) CHOSEN_MODE="update" ;;
        4) CHOSEN_MODE="reset" ;;
        *) CHOSEN_MODE="fresh" ;;
    esac
fi

case "$CHOSEN_MODE" in
    fresh)
        success "Modus: Neu-Installation"
        ;;
    add)
        success "Modus: Stack hinzufügen"
        echo ""

        # Laufende Container auf dem Pi
        RUNNING=$(docker ps -a --format '{{.Names}}' 2>/dev/null)

        echo "  Verfügbare Stacks im Profil '$CHOSEN_PROFILE':"
        FOUND=0
        for stack_dir in "$PROFILE_DIR/docker/"*/; do
            [ -f "${stack_dir}compose.yml" ] || continue
            stack=$(basename "$stack_dir")
            FOUND=1
            if echo "$RUNNING" | grep -q "^${stack}$"; then
                echo "    [läuft] $stack"
            elif [ -d "$REAL_HOME/docker/$stack" ]; then
                echo "    [stop]  $stack  (Verzeichnis vorhanden, Container gestoppt)"
            else
                echo "    [neu]   $stack"
            fi
        done

        echo ""
        echo "  Shared Stacks (für alle Profile):"
        for stack_dir in "$SHARED_DIR/docker/"*/; do
            [ -f "${stack_dir}compose.yml" ] || continue
            stack=$(basename "$stack_dir")
            FOUND=1
            if echo "$RUNNING" | grep -q "^${stack}$"; then
                echo "    [läuft] $stack"
            elif [ -d "$REAL_HOME/docker/$stack" ]; then
                echo "    [stop]  $stack"
            else
                echo "    [neu]   $stack"
            fi
        done

        [ "$FOUND" -eq 0 ] && error "Keine Stacks gefunden – Repo aktuell? git pull ausführen."

        echo ""
        read -rp "  Stack-Name eingeben: " ADD_STACK
        [ -z "$ADD_STACK" ] && error "Kein Stack angegeben."
        export ADD_STACK
        ;;
    update)
        success "Modus: Aktualisieren"
        ;;
    reset)
        success "Modus: Reset – Container neu aufbauen, Daten bleiben erhalten"
        echo ""
        warn "Alle Container werden gestoppt und neu gestartet."
        warn "Daten in ~/docker/*/data bleiben vollständig erhalten."
        echo ""
        read -rp "  Fortfahren? [j/N] " CONFIRM
        [[ "$CONFIRM" != "j" && "$CONFIRM" != "J" ]] && error "Abgebrochen."
        ;;
    *)
        error "Unbekannter Modus: $CHOSEN_MODE"
        ;;
esac

export CHOSEN_MODE

# =============================================================================
# .ENV einrichten
# =============================================================================
step ".env konfigurieren"

ENV_TARGET="$REAL_HOME/pi-admin/.env"
mkdir -p "$REAL_HOME/pi-admin"
chown "$REAL_USER:$REAL_USER" "$REAL_HOME/pi-admin"

ENV_EXAMPLE="$INSTALL_DIR/env.example"
[ -f "$INSTALL_DIR/.env.example" ] && ENV_EXAMPLE="$INSTALL_DIR/.env.example"

if [ ! -f "$ENV_TARGET" ]; then
    cp "$ENV_EXAMPLE" "$ENV_TARGET"
    chown "$REAL_USER:$REAL_USER" "$ENV_TARGET"
    chmod 600 "$ENV_TARGET"
    echo ""
    read -rp "  Telegram Bot Token: " TG_TOKEN
    read -rp "  Telegram Chat ID:   " TG_CHAT
    sed -i "s|DEIN_BOT_TOKEN_HIER|$TG_TOKEN|g" "$ENV_TARGET"
    sed -i "s|DEINE_CHAT_ID_HIER|$TG_CHAT|g" "$ENV_TARGET"
    success ".env konfiguriert"
else
    info ".env bereits vorhanden – übersprungen"
fi

# =============================================================================
# SHARED SCRIPTS installieren
# =============================================================================
step "Shared Scripts installieren"

SCRIPTS_TARGET="$REAL_HOME/pi-admin"
mkdir -p "$SCRIPTS_TARGET"

for script in "$SHARED_DIR/scripts/"*.sh; do
    TARGET="$SCRIPTS_TARGET/$(basename "$script")"
    cp "$script" "$TARGET"
    chown "$REAL_USER:$REAL_USER" "$TARGET"
    chmod 750 "$TARGET"
    success "  $(basename "$script") installiert"
done

# =============================================================================
# PROFIL ausführen
# =============================================================================
step "Profil '$CHOSEN_PROFILE' wird eingerichtet"
export REAL_USER REAL_HOME INSTALL_DIR SHARED_DIR
bash "$PROFILE_DIR/profile.sh"

# =============================================================================
# ABSCHLUSS
# =============================================================================
PI_IP=$(hostname -I | awk '{print $1}')
CRON_COUNT=$(crontab -u "$REAL_USER" -l 2>/dev/null | grep -c pi-admin || echo "0")

echo ""
echo -e "${GREEN}${BOLD}✓ Bootstrap abgeschlossen!${NC}"
echo ""
echo "  Profil:   $CHOSEN_PROFILE"
echo "  Scripts:  $SCRIPTS_TARGET"
echo "  Logs:     $SCRIPTS_TARGET/logs/"
echo "  Crontab:  $CRON_COUNT Jobs aktiv"
echo ""
echo "  Nächste Schritte:"
echo "  1. .env prüfen:     nano $ENV_TARGET"
echo "  2. Telegram testen: bash $SCRIPTS_TARGET/telegram-notify.sh"
echo "  3. Dockge:          http://${PI_IP}:5001"
echo ""