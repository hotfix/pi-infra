#!/bin/bash
# =============================================================================
# profiles/pi-dns/profile.sh – DNS-Pi mit AdGuard Home + Dockge
# Wird von bootstrap.sh aufgerufen (REAL_USER, REAL_HOME, INSTALL_DIR sind gesetzt)
# =============================================================================

PROFILE_DESC="DNS-Pi mit AdGuard Home und Dockge"

DOCKER_DIR="$REAL_HOME/docker"
BACKUP_DIR="$REAL_HOME/backup"
PI_ADMIN="$REAL_HOME/pi-admin"

info()    { echo -e "\033[0;34m[INFO]\033[0m  $*"; }
success() { echo -e "\033[0;32m[OK]\033[0m    $*"; }
warn()    { echo -e "\033[1;33m[WARN]\033[0m  $*"; }

# --- 1. Pakete installieren ---
info "Pakete installieren..."
apt-get update -qq
apt-get install -y -qq \
    curl git bc dnsutils e2fsprogs \
    ca-certificates gnupg lsb-release \
    2>/dev/null
success "Pakete installiert"

# --- 2. Docker installieren (falls nicht vorhanden) ---
if ! command -v docker &>/dev/null; then
    info "Docker wird installiert..."
    curl -fsSL https://get.docker.com | sh
    usermod -aG docker "$REAL_USER"
    systemctl enable docker
    systemctl start docker
    success "Docker installiert"
else
    info "Docker bereits vorhanden ($(docker --version | cut -d' ' -f3 | tr -d ','))"
fi

# --- 3. Verzeichnisstruktur anlegen ---
info "Verzeichnisse anlegen..."
for dir in \
    "$DOCKER_DIR/adguard/work" \
    "$DOCKER_DIR/adguard/conf" \
    "$DOCKER_DIR/dockge/data" \
    "$BACKUP_DIR/adguard" \
    "$PI_ADMIN/logs"; do
    mkdir -p "$dir"
    chown -R "$REAL_USER:$REAL_USER" "$dir"
done
success "Verzeichnisstruktur erstellt"

# --- 4. Docker Compose Files aus Repo kopieren ---
info "Docker Compose Files einrichten..."

# Profil-spezifische Stacks (z.B. adguard)
for stack_dir in "$PROFILE_DIR/docker/"*/; do
    [ -f "${stack_dir}compose.yml" ] || continue
    stack=$(basename "$stack_dir")
    mkdir -p "$DOCKER_DIR/$stack"
    cp "${stack_dir}compose.yml" "$DOCKER_DIR/$stack/compose.yml"
    chown -R "$REAL_USER:$REAL_USER" "$DOCKER_DIR/$stack"
    success "  $stack compose.yml kopiert"
done

# Gemeinsame Stacks aus shared/docker/ (z.B. dockge)
for stack_dir in "$SHARED_DIR/docker/"*/; do
    [ -f "${stack_dir}compose.yml" ] || continue
    stack=$(basename "$stack_dir")
    mkdir -p "$DOCKER_DIR/$stack"
    cp "${stack_dir}compose.yml" "$DOCKER_DIR/$stack/compose.yml"
    chown -R "$REAL_USER:$REAL_USER" "$DOCKER_DIR/$stack"
    success "  $stack compose.yml kopiert (shared)"
done

# --- 5. Container starten ---
info "Container starten..."
for stack in adguard dockge; do
    cd "$DOCKER_DIR/$stack"
    if sudo -u "$REAL_USER" docker compose ps --quiet 2>/dev/null | grep -q .; then
        info "  $stack läuft bereits"
    else
        sudo -u "$REAL_USER" docker compose up -d
        success "  $stack gestartet"
    fi
done

# --- 6. Cron-Jobs einrichten ---
info "Cron-Jobs einrichten..."

CRON_JOBS=(
    "*/5  * * * *  $PI_ADMIN/health_check.sh >> $PI_ADMIN/logs/health_check.log 2>&1"
    "*/15 * * * *  $PI_ADMIN/monitor.sh >> $PI_ADMIN/logs/monitor.log 2>&1"
    "0    4 * * 0  $PI_ADMIN/cleanup.sh >> $PI_ADMIN/logs/cleanup.log 2>&1"
    "0    6 * * 1  $PI_ADMIN/sd_health.sh >> $PI_ADMIN/logs/sd_health.log 2>&1"
    "0    3 1 * *  $PI_ADMIN/update.sh >> $PI_ADMIN/logs/update.log 2>&1"
    "0    2 * * *  $PI_ADMIN/backup_adguard.sh >> $PI_ADMIN/logs/backup.log 2>&1"
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

# --- 7. Profil-spezifische .env Ergänzungen ---
ENV_FILE="$PI_ADMIN/.env"
if ! grep -q "ADGUARD_CONF" "$ENV_FILE" 2>/dev/null; then
    cat >> "$ENV_FILE" << EOF

# --- pi-dns Profil ---
ADGUARD_CONF_DIR=${DOCKER_DIR}/adguard/conf
ADGUARD_DATA_DIR=${DOCKER_DIR}/adguard/data
EOF
fi

success "Profil pi-dns eingerichtet"