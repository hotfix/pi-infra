# Troubleshooting

---

## Bootstrap

**Clone schlägt fehl**
```bash
# Netzwerk prüfen:
ping -c 3 codeberg.org

# DNS prüfen (AdGuard noch nicht aktiv?):
nslookup codeberg.org 8.8.8.8

# Alternativ mit IP statt Hostname:
curl -v https://codeberg.org
```

**"Bitte als root ausführen"**
```bash
# bootstrap.sh benötigt sudo:
sudo bash bootstrap.sh
```

**Profil wird nicht gefunden**
```bash
# Prüfen ob profile.sh vorhanden ist:
ls ~/pi-infra/profiles/
# Jedes Profil braucht eine profile.sh direkt im Profilordner
```

---

## Telegram

**Nachrichten kommen nicht an**
```bash
# .env prüfen:
cat ~/pi-admin/.env | grep TELEGRAM

# API direkt testen:
source ~/pi-admin/.env
curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe"
# Erwartet: "ok":true

# Testnachricht senden:
curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  --data "chat_id=${TELEGRAM_CHAT_ID}&text=Test"
```

**"TELEGRAM_BOT_TOKEN nicht gesetzt"**
```bash
nano ~/pi-admin/.env
# Token und Chat-ID eintragen, Anführungszeichen beachten:
# TELEGRAM_BOT_TOKEN="123456789:ABCdef..."
```

---

## Docker

**Docker startet nicht**
```bash
systemctl status docker
journalctl -u docker --no-pager | tail -20
```

**Benutzer nicht in docker-Gruppe**
```bash
groups pi              # Sollte "docker" enthalten
sudo usermod -aG docker pi
newgrp docker          # Gruppe sofort aktivieren (oder neu einloggen)
```

**Container läuft nicht nach Bootstrap**
```bash
cd ~/docker/adguard
docker compose logs
docker compose up -d
```

**Port bereits belegt**
```bash
# Welcher Prozess nutzt den Port?
sudo ss -tlnp | grep :53
sudo lsof -i :53
```

---

## Cron

**Jobs werden nicht ausgeführt**
```bash
# Jobs anzeigen:
crontab -l

# Letzte Ausführungen:
grep -i cron /var/log/syslog | tail -20

# Script manuell testen:
bash ~/pi-admin/monitor.sh
```

**Script läuft manuell, aber nicht per Cron**

Cron hat eine minimale Umgebung – kein `$HOME`, kein `$PATH` wie im Terminal.
Alle Pfade in den Scripts sind absolut (`/home/pi/pi-admin/...`) – das sollte passen.
Falls nicht, `env` am Anfang des Scripts ausgeben lassen:

```bash
# In crontab temporär hinzufügen:
* * * * * env > /tmp/cron-env.txt
```

---

## Speicher & SD-Karte

**SD-Karte voll**
```bash
df -h                          # Übersicht
du -sh ~/* 2>/dev/null         # Wo liegt der Speicher?
sudo bash ~/pi-admin/cleanup.sh   # Manuell bereinigen
docker system df               # Docker Speicherverbrauch
docker system prune -f         # Docker aufräumen
```

**I/O-Fehler auf der SD-Karte**
```bash
dmesg | grep -i "mmc\|error" | tail -20
# Sofort Backup erstellen!
bash ~/pi-admin/backup_adguard.sh
```

> Bei I/O-Fehlern auf der SD-Karte zeitnah eine neue SD-Karte besorgen –
> SD-Karten geben beim Pi oft ohne weitere Vorwarnung auf.

---

## AdGuard

**AdGuard blockiert Docker Hub (langsamer Pull)**
```bash
# DNS-Auflösung testen:
nslookup registry-1.docker.io 127.0.0.1

# Falls blockiert: in AdGuard unter Allowlist eintragen:
# registry-1.docker.io
# production.cloudflare.docker.com
```

**AdGuard Web-UI nicht erreichbar**
```bash
docker ps | grep adguard
cd ~/docker/adguard && docker compose up -d
# Web-UI: http://PI_IP:3000
```