#!/bin/bash
# =============================================================================
# monitor.sh – Mini-Monitoring: CPU, RAM, Temperatur, Disk
# Empfohlener Cron: */15 * * * * /home/pi/pi-admin/monitor.sh
# =============================================================================

source ~/pi-admin/telegram_notify.sh

LOG_FILE=~/pi-admin/logs/monitor.log
mkdir -p ~/pi-admin/logs

# --- Schwellwerte aus .env ---
CPU_WARN="${CPU_WARN:-80}"
RAM_WARN="${RAM_WARN:-85}"
TEMP_WARN="${TEMP_WARN:-70}"
DISK_WARN="${DISK_WARN:-85}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# --- Metriken sammeln ---

# CPU (1-Minuten-Durchschnitt)
CPU_LOAD=$(awk '{printf "%.0f", $1 * 100}' /proc/loadavg)
CPU_CORES=$(nproc)
CPU_PERCENT=$((CPU_LOAD / CPU_CORES))

# Top 3 CPU-Prozesse
CPU_TOP=$(ps aux --sort=-%cpu | awk 'NR==2,NR==4 {printf "  %-20s %s%%\n", $11, $3}')

# RAM
RAM_INFO=$(free | awk '/^Mem:/ {printf "%.0f %.0f %.0f", $3/$2*100, $2/1024, $3/1024}')
RAM_PERCENT=$(echo "$RAM_INFO" | awk '{print $1}')
RAM_TOTAL_MB=$(echo "$RAM_INFO" | awk '{print $2}')
RAM_USED_MB=$(echo "$RAM_INFO" | awk '{print $3}')

# Top 3 RAM-Prozesse
RAM_TOP=$(ps aux --sort=-%mem | awk 'NR==2,NR==4 {printf "  %-20s %s%%\n", $11, $4}')

# Swap
SWAP_PERCENT=$(free | awk '/^Swap:/ {if($2>0) printf "%.0f", $3/$2*100; else print "0"}')

# Temperatur
if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    TEMP_RAW=$(cat /sys/class/thermal/thermal_zone0/temp)
    TEMP=$(echo "scale=1; $TEMP_RAW / 1000" | bc)
    TEMP_INT=$(echo "$TEMP" | cut -d'.' -f1)
else
    TEMP="unbekannt"
    TEMP_INT=0
fi

# CPU-Drosselung prüfen (Pi-spezifisch)
THROTTLED=""
if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]; then
    CUR_FREQ=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)
    MAX_FREQ=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq)
    if [ "$CUR_FREQ" -lt "$MAX_FREQ" ]; then
        CUR_MHZ=$((CUR_FREQ / 1000))
        MAX_MHZ=$((MAX_FREQ / 1000))
        THROTTLED="⚠️ CPU gedrosselt: ${CUR_MHZ}MHz von ${MAX_MHZ}MHz"
    fi
fi

# Disk
DISK_PERCENT=$(df / | awk 'NR==2 {printf "%.0f", $5}' | tr -d '%')
DISK_FREE=$(df -h / | awk 'NR==2 {print $4}')
DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
DISK_USED=$(df -h / | awk 'NR==2 {print $3}')

# Uptime & Load
UPTIME=$(uptime -p | sed 's/up //')
LOAD_1=$(awk '{print $1}' /proc/loadavg)
LOAD_5=$(awk '{print $2}' /proc/loadavg)
LOAD_15=$(awk '{print $3}' /proc/loadavg)

log "CPU: ${CPU_PERCENT}% | RAM: ${RAM_PERCENT}% (${RAM_USED_MB}/${RAM_TOTAL_MB}MB) | Temp: ${TEMP}°C | Disk: ${DISK_PERCENT}% | Load: ${LOAD_1} ${LOAD_5} ${LOAD_15}"

# --- Alerts prüfen ---
ALERTS=()

[ "$CPU_PERCENT"  -ge "$CPU_WARN"  ] && ALERTS+=("cpu")
[ "$RAM_PERCENT"  -ge "$RAM_WARN"  ] && ALERTS+=("ram")
[ "$TEMP_INT"     -ge "$TEMP_WARN" ] && ALERTS+=("temp")
[ "$DISK_PERCENT" -ge "$DISK_WARN" ] && ALERTS+=("disk")

if [ ${#ALERTS[@]} -gt 0 ]; then

    # --- Alert-Details je Typ aufbauen ---
    ALERT_DETAILS=""

    for alert in "${ALERTS[@]}"; do
        case "$alert" in
            cpu)
                ALERT_DETAILS+="
🔥 *CPU: ${CPU_PERCENT}%* (Schwellwert: ${CPU_WARN}%)
  Load: ${LOAD_1} / ${LOAD_5} / ${LOAD_15} (1/5/15 min)
  Top Prozesse:
${CPU_TOP}
  📋 Prüfen:  \`top -b -n1 | head -20\`
  🔧 Fixen:   \`kill -9 <PID>\` oder Service neu starten"
                [ -n "$THROTTLED" ] && ALERT_DETAILS+="
  ${THROTTLED}"
                ;;
            ram)
                ALERT_DETAILS+="
💾 *RAM: ${RAM_PERCENT}%* (${RAM_USED_MB}MB von ${RAM_TOTAL_MB}MB, Schwellwert: ${RAM_WARN}%)
  Swap: ${SWAP_PERCENT}% belegt
  Top Prozesse:
${RAM_TOP}
  📋 Prüfen:  \`free -h\` und \`ps aux --sort=-%mem | head -10\`
  🔧 Fixen:   \`docker restart <container>\` oder Pi neu starten"
                ;;
            temp)
                ALERT_DETAILS+="
🌡️ *Temperatur: ${TEMP}°C* (Schwellwert: ${TEMP_WARN}°C, Drossel ab 80°C)
  ${THROTTLED:-CPU läuft noch mit voller Leistung}
  📋 Prüfen:  \`vcgencmd measure_temp\`
  🔧 Fixen:   Gehäuse-Lüftung verbessern, Last reduzieren"
                ;;
            disk)
                ALERT_DETAILS+="
💽 *Disk: ${DISK_PERCENT}%* (${DISK_USED} von ${DISK_TOTAL}, noch ${DISK_FREE} frei)
  📋 Prüfen:  \`df -h\` und \`du -sh ~/*\`
  🔧 Fixen:   \`sudo bash ~/pi-admin/cleanup.sh\`
              \`docker system prune -f\`"
                ;;
        esac
    done

    send_telegram "*Monitor Alert* – ${#ALERTS[@]} Problem(e)
━━━━━━━━━━━━━━━━━━━━
${ALERT_DETAILS}
━━━━━━━━━━━━━━━━━━━━
🖥️ Uptime: ${UPTIME}
📄 Log: \`tail -20 ~/pi-admin/logs/monitor.log\`" "🚨"

    log "ALERT gesendet: ${ALERTS[*]}"
fi