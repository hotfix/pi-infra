#!/bin/bash
# =============================================================================
# monitor.sh – Mini-Monitoring: CPU, RAM, Temperatur, Disk
# Empfohlener Cron: */15 * * * * /home/pi/pi-admin/monitor.sh
# =============================================================================

source ~/pi-admin/telegram_notify.sh

LOG_FILE=~/pi-admin/logs/monitor.log
mkdir -p ~/pi-admin/logs

# --- Schwellwerte aus .env (gesetzt via telegram_notify.sh) ---
CPU_WARN="${CPU_WARN:-80}"
RAM_WARN="${RAM_WARN:-85}"
TEMP_WARN="${TEMP_WARN:-70}"
DISK_WARN="${DISK_WARN:-85}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# --- Metriken sammeln ---

# CPU (1-Minuten-Durchschnitt, skaliert auf %)
CPU_LOAD=$(awk '{printf "%.0f", $1 * 100}' /proc/loadavg)
CPU_CORES=$(nproc)
CPU_PERCENT=$((CPU_LOAD / CPU_CORES))

# RAM
RAM_INFO=$(free | awk '/^Mem:/ {printf "%.0f %.0f", $3/$2*100, $2/1024/1024}')
RAM_PERCENT=$(echo "$RAM_INFO" | awk '{print $1}')
RAM_TOTAL_GB=$(echo "$RAM_INFO" | awk '{print $2}')

# Swap
SWAP_PERCENT=$(free | awk '/^Swap:/ {if($2>0) printf "%.0f", $3/$2*100; else print "0"}')

# Temperatur (Pi-spezifisch)
if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    TEMP_RAW=$(cat /sys/class/thermal/thermal_zone0/temp)
    TEMP=$(echo "scale=1; $TEMP_RAW / 1000" | bc)
    TEMP_INT=$(echo "$TEMP" | cut -d'.' -f1)
else
    TEMP="unbekannt"
    TEMP_INT=0
fi

# Disk (/)
DISK_PERCENT=$(df / | awk 'NR==2 {printf "%.0f", $5}' | tr -d '%')
DISK_FREE=$(df -h / | awk 'NR==2 {print $4}')

# Uptime
UPTIME=$(uptime -p | sed 's/up //')

# --- Loggen ---
log "CPU: ${CPU_PERCENT}% | RAM: ${RAM_PERCENT}% | Temp: ${TEMP}°C | Disk: ${DISK_PERCENT}% | Uptime: ${UPTIME}"

# --- Alerts prüfen ---
ALERTS=()
ALERT_EMOJI="✅"

[ "$CPU_PERCENT" -ge "$CPU_WARN" ] && ALERTS+=("🔥 CPU: ${CPU_PERCENT}% (>${CPU_WARN}%)")
[ "$RAM_PERCENT" -ge "$RAM_WARN" ] && ALERTS+=("💾 RAM: ${RAM_PERCENT}% (>${RAM_WARN}%)")
[ "$TEMP_INT" -ge "$TEMP_WARN" ] && ALERTS+=("🌡️ Temperatur: ${TEMP}°C (>${TEMP_WARN}°C)")
[ "$DISK_PERCENT" -ge "$DISK_WARN" ] && ALERTS+=("💽 Disk: ${DISK_PERCENT}% (>${DISK_WARN}%)")

# Nur senden wenn Alert ausgelöst
if [ ${#ALERTS[@]} -gt 0 ]; then
    ALERT_MSG=$(printf '%s\n' "${ALERTS[@]}")
    send_telegram "⚠️ *Alert!*
${ALERT_MSG}

RAM gesamt: ${RAM_TOTAL_GB} GB | Swap: ${SWAP_PERCENT}%
Freier Disk: ${DISK_FREE}
Uptime: ${UPTIME}" "🚨"
    log "ALERT gesendet: ${ALERTS[*]}"
fi
