#!/bin/bash
# =============================================================================
# profiles/pi-home/profile.sh – Home-Pi
# Stacks: Uptime Kuma, Syncthing, Nginx Proxy Manager, Dockge
# Wird von bootstrap.sh aufgerufen (REAL_USER, REAL_HOME, INSTALL_DIR gesetzt)
# =============================================================================

PROFILE_DESC="Home-Pi mit Uptime Kuma, Syncthing und Nginx Proxy Manager"

DOCKER_DIR="$REAL_HOME/docker"
BACKUP_DIR="$REAL_HOME/backup"
PI_ADMIN="$REAL_HOME/pi-admin"
PROFILE_DIR="$INSTALL_DIR/profiles/pi-home"

info()    { echo -e "\033[0;34m[INFO]\033[0m  $*"; }
success() { echo -e "\033[0;32m[OK]\033[0m    $*"; }
warn()    { echo -e "\033[1;33m[WARN]\033[0m  $*"; }

# --- 1. Pakete ---
info "Pakete installieren..."
apt-get update -qq
apt-get install -y -qq \
    curl git bc dnsutils e2fsprogs \
    ca-certificates gnupg lsb-release \
    2>/dev/null
success "Pakete installiert"

# --- 2. Docker ---
if ! command -v docker &>/dev/null; then
    info "Docker wird installiert..."
    curl -fsSL https://get.docker.com | sh
    usermod -aG docker "$REAL_USER"
    systemctl enable docker
    systemctl start docker
    success "Docker installiert"
else
    info "Docker bereits vorhanden"
fi

# --- 3. Verzeichnisstruktur ---
info "Verzeichnisse anlegen..."
for dir in \
    "$DOCKER_DIR/uptime-kuma/data" \
    "$DOCKER_DIR/syncthing/config" \
    "$DOCKER_DIR/nginx-proxy-manager/data" \
    "$DOCKER_DIR/nginx-proxy-manager/letsencrypt" \
    "$DOCKER_DIR/dockge/data" \
    "$REAL_HOME/sync" \
    "$BACKUP_DIR" \
    "$PI_ADMIN/logs"; do
    mkdir -p "$dir"
    chown -R "$REAL_USER:$REAL_USER" "$dir"
done
success "Verzeichnisstruktur erstellt"

# --- 4. Compose Files aus Repo kopieren ---
info "Docker Compose Files einrichten (Modus: ${CHOSEN_MODE:-fresh})..."

# Im add-Modus nur den gewählten Stack installieren
if [ "${CHOSEN_MODE:-fresh}" = "add" ] && [ -n "${ADD_STACK:-}" ]; then
    info "Füge Stack hinzu: $ADD_STACK"
    STACK_SRC="$PROFILE_DIR/docker/$ADD_STACK"
    # Auch shared/docker prüfen
    [ ! -d "$STACK_SRC" ] && STACK_SRC="$SHARED_DIR/docker/$ADD_STACK"
    if [ ! -d "$STACK_SRC" ]; then
        error "Stack nicht gefunden: $ADD_STACK"
    fi
    mkdir -p "$DOCKER_DIR/$ADD_STACK"
    cp "$STACK_SRC/compose.yml" "$DOCKER_DIR/$ADD_STACK/compose.yml"
    chown -R "$REAL_USER:$REAL_USER" "$DOCKER_DIR/$ADD_STACK"
    cd "$DOCKER_DIR/$ADD_STACK"
    sudo -u "$REAL_USER" docker compose up -d
    success "$ADD_STACK gestartet"
    exit 0
fi

# Im update-Modus Compose Files aktualisieren und Container neu starten
if [ "${CHOSEN_MODE:-fresh}" = "update" ]; then
    info "Aktualisiere Compose Files und starte Container neu..."
    for stack_dir in "$PROFILE_DIR/docker/"*/; do
        [ -f "${stack_dir}compose.yml" ] || continue
        stack=$(basename "$stack_dir")
        if [ -d "$DOCKER_DIR/$stack" ]; then
            cp "${stack_dir}compose.yml" "$DOCKER_DIR/$stack/compose.yml"
            chown -R "$REAL_USER:$REAL_USER" "$DOCKER_DIR/$stack"
            cd "$DOCKER_DIR/$stack"
            sudo -u "$REAL_USER" docker compose pull -q 2>/dev/null
            sudo -u "$REAL_USER" docker compose up -d
            success "  $stack aktualisiert"
        fi
    done
    # Shared stacks auch aktualisieren
    for stack_dir in "$SHARED_DIR/docker/"*/; do
        [ -f "${stack_dir}compose.yml" ] || continue
        stack=$(basename "$stack_dir")
        if [ -d "$DOCKER_DIR/$stack" ]; then
            cp "${stack_dir}compose.yml" "$DOCKER_DIR/$stack/compose.yml"
            chown -R "$REAL_USER:$REAL_USER" "$DOCKER_DIR/$stack"
            cd "$DOCKER_DIR/$stack"
            sudo -u "$REAL_USER" docker compose pull -q 2>/dev/null
            sudo -u "$REAL_USER" docker compose up -d
            success "  $stack aktualisiert (shared)"
        fi
    done
    exit 0
fi

for stack_dir in "$PROFILE_DIR/docker/"*/; do
    [ -f "${stack_dir}compose.yml" ] || continue
    stack=$(basename "$stack_dir")
    mkdir -p "$DOCKER_DIR/$stack"
    cp "${stack_dir}compose.yml" "$DOCKER_DIR/$stack/compose.yml"
    chown -R "$REAL_USER:$REAL_USER" "$DOCKER_DIR/$stack"
    success "  $stack compose.yml kopiert"
done

for stack_dir in "$SHARED_DIR/docker/"*/; do
    [ -f "${stack_dir}compose.yml" ] || continue
    stack=$(basename "$stack_dir")
    mkdir -p "$DOCKER_DIR/$stack"
    cp "${stack_dir}compose.yml" "$DOCKER_DIR/$stack/compose.yml"
    chown -R "$REAL_USER:$REAL_USER" "$DOCKER_DIR/$stack"
    success "  $stack compose.yml kopiert (shared)"
done


# --- 6. Container starten ---
info "Container starten..."
for stack in uptime-kuma syncthing nginx-proxy-manager dockge; do
    cd "$DOCKER_DIR/$stack" || continue
    if sudo -u "$REAL_USER" docker compose ps --quiet 2>/dev/null | grep -q .; then
        info "  $stack läuft bereits"
    else
        sudo -u "$REAL_USER" docker compose up -d 2>/dev/null
        success "  $stack gestartet"
    fi
done

# --- 7. Cron-Jobs ---
info "Cron-Jobs einrichten..."

CRON_JOBS=(
    "*/5  * * * *  $PI_ADMIN/health-check.sh >> $PI_ADMIN/logs/health-check.log 2>&1"
    "*/15 * * * *  $PI_ADMIN/monitor.sh >> $PI_ADMIN/logs/monitor.log 2>&1"
    "0    4 * * 0  sudo $PI_ADMIN/cleanup.sh >> $PI_ADMIN/logs/cleanup.log 2>&1"
    "0    6 * * 1  $PI_ADMIN/sd-health.sh >> $PI_ADMIN/logs/sd-health.log 2>&1"
    "0    3 1 * *  $PI_ADMIN/update.sh >> $PI_ADMIN/logs/update.log 2>&1"
)

CURRENT_CRON=$(crontab -u "$REAL_USER" -l 2>/dev/null || echo "")
NEW_CRON="$CURRENT_CRON"
for job in "${CRON_JOBS[@]}"; do
    script=$(echo "$job" | awk '{print $6}')
    if ! echo "$CURRENT_CRON" | grep -qF "$script"; then
        NEW_CRON="${NEW_CRON}"$'\n'"$job"
        success "  Cron hinzugefügt: $(basename "$script")"
    fi
done
echo "$NEW_CRON" | crontab -u "$REAL_USER" -
success "Cron-Jobs eingerichtet"

# --- 8. sudoers für cleanup.sh ---
SUDOERS_FILE="/etc/sudoers.d/pi-admin"
if [ ! -f "$SUDOERS_FILE" ]; then
    echo "$REAL_USER ALL=(ALL) NOPASSWD: $PI_ADMIN/cleanup.sh" > "$SUDOERS_FILE"
    chmod 440 "$SUDOERS_FILE"
    success "sudoers Eintrag angelegt"
fi

# --- 9. Profil-spezifische Scripts installieren ---
info "Profil-Scripts installieren..."
PROFILE_SCRIPTS_DIR="$PROFILE_DIR/scripts"
if [ -d "$PROFILE_SCRIPTS_DIR" ]; then
    for script in "$PROFILE_SCRIPTS_DIR/"*.sh; do
        [ -f "$script" ] || continue
        TARGET="$PI_ADMIN/$(basename "$script")"
        cp "$script" "$TARGET"
        chown "$REAL_USER:$REAL_USER" "$TARGET"
        chmod 750 "$TARGET"
        success "  $(basename "$script") installiert"
    done
fi

# --- 10. .env Ergänzungen ---
ENV_FILE="$PI_ADMIN/.env"

# --- Abschluss ---
success "Profil pi-home eingerichtet"
echo ""
info "Erreichbare Dienste:"
PI_IP=$(hostname -I | awk '{print $1}')
info "  Uptime Kuma:         http://${PI_IP}:3001"
info "  Syncthing:           http://${PI_IP}:8384"
info "  Nginx Proxy Manager: http://${PI_IP}:81  (admin@example.com / changeme)"
info "  Dockge:              http://${PI_IP}:5001"
info ""
warn "Nginx PM:  Standard-Passwort nach erstem Login sofort ändern!"