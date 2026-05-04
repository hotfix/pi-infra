# Profile

Ein Profil definiert die Rolle eines Pi – welche Container laufen,
welche Scripts installiert werden und welche Cron-Jobs aktiv sind.

---

## Verfügbare Profile

### `pi-dns`
DNS-Pi mit AdGuard Home als netzwerkweitem Werbeblocker.

| Stack | Port | Zweck |
|-------|------|-------|
| AdGuard Home | 3000 (Setup), 80/443, 53 | DNS + Werbeblocker |
| Dockge | 5001 | Docker UI |

Cron-Jobs: alle 5 min health-check, alle 15 min monitor, täglich backup,
wöchentlich cleanup + sd-health, monatlich update.


### `pi-home`
Home-Pi als zentraler Dienste-Knoten für das Heimnetz.

| Stack | Port | Zweck |
|-------|------|-------|
| Uptime Kuma | 3001 | Monitoring – überwacht beide Pis + AdGuard |
| Syncthing | 8384 | Dateisync ohne Cloud |
| Nginx Proxy Manager | 80, 443, 81 | Reverse Proxy + SSL |
| Dockge | 5001 | Docker UI |

Cron-Jobs: alle 5 min health-check, alle 15 min monitor, täglich backup-home,
wöchentlich cleanup + sd-health, monatlich update.


---

## Profil beim Bootstrap wählen

```bash
# Interaktiv (empfohlen):
sudo bash bootstrap.sh

# Direkt angeben:
sudo bash bootstrap.sh pi-dns
```

---

## Neues Profil anlegen

Ein Profil besteht mindestens aus einer `profile.sh`.
Als Vorlage einfach ein bestehendes kopieren:

```bash
cp -r profiles/pi-dns profiles/mein-pi
nano profiles/mein-pi/profile.sh
```

Die wichtigsten Felder in `profile.sh`:

```bash
PROFILE_DESC="Kurze Beschreibung"   # Wird im Bootstrap-Menü angezeigt

# Pakete, Docker-Setup, Verzeichnisse, Cron-Jobs ...
```

Docker Compose Files für das neue Profil:

```bash
mkdir -p profiles/mein-pi/docker/mein-stack
nano profiles/mein-pi/docker/mein-stack/compose.yml
```

`profile.sh` kopiert automatisch alle `compose.yml` aus `profiles/mein-pi/docker/`
sowie alle gemeinsamen Stacks aus `shared/docker/` – kein weiteres Script nötig.

Commit und Push:

```bash
git add profiles/mein-pi/
git commit -m "feat: add mein-pi profile"
git push
```

---

## Shared Scripts

Alle Profile erhalten automatisch diese Scripts unter `~/pi-admin/`:

| Script | Intervall | Funktion |
|--------|-----------|----------|
| `telegram-notify.sh` | – | Zentrale Benachrichtigungsfunktion |
| `monitor.sh` | alle 15 min | CPU, RAM, Temperatur, Disk |
| `health-check.sh` | alle 5 min | Docker Container + DNS |
| `cleanup.sh` | So. 04:00 | Speicher & Logs bereinigen |
| `sd-health.sh` | Mo. 06:00 | SD-Karten Gesundheit |
| `update.sh` | 1. des Monats | Systemupdates + Docker Images |

---

Vollständige Cron-Übersicht mit Zeiten und Anpassungshinweisen: [docs/cron.md](cron.md)