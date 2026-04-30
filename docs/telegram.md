# Telegram Bot einrichten

Alle pi-admin Scripts benachrichtigen dich via Telegram.
Du brauchst einen **Bot Token** und deine persönliche **Chat-ID**.

---

## Schritt 1 – Bot erstellen

1. Öffne Telegram und suche nach `@BotFather`
2. Sende `/newbot`
3. Wähle einen Anzeigenamen, z.B. `RaspyGuard`
4. Wähle einen Username – muss auf `bot` enden, z.B. `RaspyGuardBot`
5. BotFather antwortet mit deinem Token:
   ```
   123456789:ABCdefGHIjklMNOpqrSTUvwxYZ
   ```
   → Diesen Token sicher notieren, er wird in der `.env` eingetragen.

---

## Schritt 2 – Chat-ID herausfinden

1. Suche deinen neuen Bot in Telegram und sende ihm `/start`
2. Öffne folgenden Link im Browser (Token ersetzen):
   ```
   https://api.telegram.org/bot123456789:ABCdef.../getUpdates
   ```
3. In der JSON-Antwort findest du deine Chat-ID:
   ```json
   {"message":{"chat":{"id": 987654321, ...}}}
   ```
   Die Zahl hinter `"id"` ist deine Chat-ID.

> **Tipp:** Falls die Antwort leer ist (`"result":[]`) – nochmal `/start`
> an den Bot senden und die URL neu laden.

---

## Schritt 3 – Bot testen

Vor dem Pi-Setup schnell prüfen ob alles stimmt:

```bash
curl -s -X POST "https://api.telegram.org/botDEIN_TOKEN/sendMessage" \
  --data "chat_id=DEINE_CHAT_ID&text=Hallo+vom+Pi!"
```

Kommt `"ok":true` zurück und eine Nachricht in Telegram? Dann passt alles.

---

## Schritt 4 – In .env eintragen

`bootstrap.sh` fragt beim ersten Setup automatisch nach Token und Chat-ID.

Nachträglich ändern:

```bash
nano ~/pi-admin/.env
```

```bash
TELEGRAM_BOT_TOKEN="123456789:ABCdef..."
TELEGRAM_CHAT_ID="987654321"
```

Danach Berechtigungen prüfen:

```bash
chmod 600 ~/pi-admin/.env
ls -la ~/pi-admin/.env
# Erwartet: -rw------- 1 pi pi ...
```

---

## Was wird gemeldet?

| Script | Meldet |
|--------|--------|
| `monitor.sh` | Alert wenn CPU/RAM/Temp/Disk Schwellwert überschritten |
| `health_check.sh` | Container down oder DNS-Ausfall |
| `sd_health.sh` | I/O-Fehler, Bad Blocks, FS-Fehler auf der SD-Karte |
| `update.sh` | Ergebnis des monatlichen Systemupdates |
| `cleanup.sh` | Nur wenn viel Speicher befreit wurde oder Disk noch voll |

Schwellwerte für Alerts sind in `~/pi-admin/.env` konfigurierbar.