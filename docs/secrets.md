# Secrets & .env

Alle sensiblen Daten – Tokens, Passwörter, Pfade – liegen in `~/pi-admin/.env`
auf dem Pi. Diese Datei ist **nicht** im Repo und wird nie eingecheckt.

---

## Prinzip

```
Repo (Codeberg)          Pi (lokal)
─────────────────        ──────────────────
.env.example    →  copy  ~/pi-admin/.env
(Vorlage, leer)          (echte Werte, geheim)
```

`bootstrap.sh` kopiert `.env.example` beim ersten Setup nach `~/pi-admin/.env`
und fragt interaktiv nach Telegram Token und Chat-ID.

---

## Alle Variablen

```bash
# --- Telegram ---
TELEGRAM_BOT_TOKEN=""     # Token von @BotFather
TELEGRAM_CHAT_ID=""       # Deine persönliche Chat-ID

# --- Verzeichnisse ---
PI_ADMIN_DIR="$HOME/pi-admin"
BACKUP_DIR="$HOME/backup"
DOCKER_DIR="$HOME/docker"

# --- Monitoring Schwellwerte ---
CPU_WARN=80               # % CPU-Auslastung
RAM_WARN=85               # % RAM-Auslastung
TEMP_WARN=70              # °C – Pi 3B drosselt ab 80°C
DISK_WARN=85              # % Disk-Auslastung

# --- Backup ---
BACKUP_MAX_AGE_DAYS=30    # Backups älter als X Tage löschen

# --- Logging ---
LOG_MAX_AGE_DAYS=60       # Script-Logs älter als X Tage löschen
```

---

## .env bearbeiten

```bash
nano ~/pi-admin/.env
```

Berechtigungen prüfen – nur dein Benutzer darf lesen:

```bash
chmod 600 ~/pi-admin/.env
ls -la ~/pi-admin/.env
# Erwartet: -rw------- 1 pi pi ...
```

---

## Sicherheit

- `.env` steht in `.gitignore` – kann nicht versehentlich gepusht werden
- Nur `.env.example` (ohne echte Werte) liegt im Repo
- `telegram_notify.sh` prüft beim Start ob Token und Chat-ID gesetzt sind
  und bricht mit einer Fehlermeldung ab falls nicht

Niemals Token oder Chat-ID direkt in ein Script hardcoden –
immer über die `.env` verwalten.

---

## .env auf mehrere Pis übertragen

Die `.env` nicht per Git verteilen. Stattdessen einmalig sicher kopieren:

```bash
# Von Rechner auf Pi (einmalig):
scp ~/pi-admin/.env pi@PI_IP:~/pi-admin/.env

# Oder direkt auf dem neuen Pi nach dem Bootstrap:
nano ~/pi-admin/.env
```