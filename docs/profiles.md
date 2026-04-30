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

Cron-Jobs: alle 5 min health_check, alle 15 min monitor, täglich backup,
wöchentlich cleanup + sd_health, monatlich update.

### `pi-media`
Media-Pi mit Jellyfin als Medienserver.

| Stack | Port | Zweck |
|-------|------|-------|
| Jellyfin | 8096 | Medienserver |
| Dockge | 5001 | Docker UI |

Cron-Jobs: wie pi-dns aber monitor alle 30 min (schont RAM).

### `pi-home` *(Vorlage)*
Noch nicht implementiert – als Ausgangspunkt für Home Assistant o.ä. gedacht.

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
| `telegram_notify.sh` | – | Zentrale Benachrichtigungsfunktion |
| `monitor.sh` | alle 15 min | CPU, RAM, Temperatur, Disk |
| `health_check.sh` | alle 5 min | Docker Container + DNS |
| `cleanup.sh` | So. 04:00 | Speicher & Logs bereinigen |
| `sd_health.sh` | Mo. 06:00 | SD-Karten Gesundheit |
| `update.sh` | 1. des Monats | Systemupdates + Docker Images |