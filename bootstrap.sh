#!/bin/bash
# =============================================================================
# bootstrap.sh – Pi Infrastruktur Einstiegspunkt
#
# Frischer Pi, ein Befehl:
#   bash <(curl -s https://codeberg.org/DEIN_USER/pi-infra/raw/branch/main/bootstrap.sh)
#
# Oder nach manuellem Clone:
#   git clone https://codeberg.org/DEIN_USER/pi-infra.git && cd pi-infra
#   bash bootstrap.sh [profil]
# =============================================================================

set -euo pipefail

REPO_URL="https://codeberg.org/DEIN_USER/pi-infra"
INSTALL_DIR="$HOME/pi-infra"
SHARED_DIR="$INSTALL_DIR/shared"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step()    { echo -e "\n${BOLD}──────────────────────────────${NC}"; echo -e "${BOLD} $*${NC}"; echo -e "${BOLD}──────────────────────────────${NC}"; }

# --- Root prüfen ---
if [ "$EUID" -ne 0 ]; then
    error "Bitte als root ausführen: sudo bash bootstrap.sh"
fi

REAL_USER="${SUDO_USER:-pi}"
REAL_HOME=$(eval echo "~$REAL_USER")

echo ""
echo -e "${BOLD}  Pi Infrastruktur Bootstrap${NC}"
echo -e "  Benutzer: ${REAL_USER} | Host: $(hostname)"
echo ""

# --- Repo clonen oder aktualisieren ---
step "Repo einrichten"
if [ ! -d "$INSTALL_DIR/.git" ]; then
    info "Cloning von $REPO_URL ..."
    sudo -u "$REAL_USER" git clone "$REPO_URL" "$INSTALL_DIR" \
        || error "Clone fehlgeschlagen. URL korrekt? Netzwerk ok?"
    success "Repo geclont nach $INSTALL_DIR"
else
    info "Repo bereits vorhanden, aktualisiere..."
    sudo -u "$REAL_USER" git -C "$INSTALL_DIR" pull --ff-only
    success "Repo aktualisiert"
fi

# --- Profil wählen ---
step "Profil wählen"

PROFILES=()
for dir in "$INSTALL_DIR/profiles"/*/; do
    [ -f "${dir}profile.sh" ] && PROFILES+=("$(basename "$dir")")
done

if [ ${#PROFILES[@]} -eq 0 ]; then
    error "Keine Profile gefunden in $INSTALL_DIR/profiles/"
fi

# Profil aus Argument oder interaktiv
CHOSEN_PROFILE="${1:-}"
if [ -z "$CHOSEN_PROFILE" ]; then
    echo "Verfügbare Profile:"
    for i in "${!PROFILES[@]}"; do
        PROFILE="${PROFILES[$i]}"
        DESC=""
        [ -f "$INSTALL_DIR/profiles/$PROFILE/profile.sh" ] && \
            DESC=$(grep "^PROFILE_DESC=" "$INSTALL_DIR/profiles/$PROFILE/profile.sh" | cut -d'"' -f2)
        echo "  $((i+1))) $PROFILE  – $DESC"
    done
    echo ""
    read -rp "Profil wählen [1-${#PROFILES[@]}]: " CHOICE
    CHOSEN_PROFILE="${PROFILES[$((CHOICE-1))]}"
fi

PROFILE_DIR="$INSTALL_DIR/profiles/$CHOSEN_PROFILE"
[ -f "$PROFILE_DIR/profile.sh" ] || error "Profil nicht gefunden: $CHOSEN_PROFILE"

success "Gewähltes Profil: $CHOSEN_PROFILE"

# --- .env einrichten ---
step ".env konfigurieren"
ENV_TARGET="$REAL_HOME/pi-admin/.env"
mkdir -p "$REAL_HOME/pi-admin"

if [ ! -f "$ENV_TARGET" ]; then
    cp "$INSTALL_DIR/.env.example" "$ENV_TARGET"
    chown "$REAL_USER:$REAL_USER" "$ENV_TARGET"
    chmod 600 "$ENV_TARGET"
    warn ".env wurde angelegt aus .env.example"
    warn "Bitte jetzt ausfüllen: nano $ENV_TARGET"
    echo ""
    read -rp "Telegram Bot Token: " TG_TOKEN
    read -rp "Telegram Chat ID:   " TG_CHAT
    sed -i "s|DEIN_BOT_TOKEN_HIER|$TG_TOKEN|g" "$ENV_TARGET"
    sed -i "s|DEINE_CHAT_ID_HIER|$TG_CHAT|g" "$ENV_TARGET"
    success ".env konfiguriert"
else
    info ".env bereits vorhanden – übersprungen"
fi

# --- Gemeinsame Scripts installieren ---
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

# --- Profil ausführen ---
step "Profil '$CHOSEN_PROFILE' wird eingerichtet"
export REAL_USER REAL_HOME INSTALL_DIR SHARED_DIR
bash "$PROFILE_DIR/profile.sh"

# --- Abschluss ---
echo ""
echo -e "${GREEN}${BOLD}✓ Bootstrap abgeschlossen!${NC}"
echo ""
echo "  Profil:   $CHOSEN_PROFILE"
echo "  Scripts:  $SCRIPTS_TARGET"
echo "  Logs:     $SCRIPTS_TARGET/logs/"
echo "  Crontab:  $(crontab -u "$REAL_USER" -l 2>/dev/null | grep -c pi-admin) Jobs aktiv"
echo ""
echo "  Nächste Schritte:"
echo "  1. .env prüfen:          nano $ENV_TARGET"
echo "  2. Telegram testen:      sudo -u $REAL_USER bash $SCRIPTS_TARGET/telegram_notify.sh test"
echo "  3. AdGuard aufrufen:     http://$(hostname -I | awk '{print $1}'):3000"
echo ""