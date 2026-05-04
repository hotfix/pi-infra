# Cron-Jobs

Alle Cron-Jobs werden beim Bootstrap **automatisch** eingerichtet –
kein manuelles Eingreifen nötig.

Prüfen ob alles angelegt wurde:
```bash
crontab -l
```

---

## Übersicht aller Jobs

### Profil `pi-dns`

| Script | Wann genau | Cron-Ausdruck | Warum diese Zeit |
|--------|-----------|---------------|-----------------|
| `health-check.sh` | Alle 5 Minuten, rund um die Uhr | `*/5 * * * *` | Schnelle Reaktion bei Container-Ausfall |
| `monitor.sh` | Alle 15 Minuten, rund um die Uhr | `*/15 * * * *` | Ressourcenüberwachung, Pi 3B schonen |
| `backup-adguard.sh` | Täglich um 02:00 Uhr nachts | `0 2 * * *` | Wenig DNS-Last, kurze Downtime unbemerkt |
| `cleanup.sh` | Jeden Sonntag um 04:00 Uhr nachts | `0 4 * * 0` | Wöchentlich, Pi ist idle |
| `sd-health.sh` | Jeden Montag um 06:00 Uhr früh | `0 6 * * 1` | Wöchentlicher Gesundheitsbericht |
| `update.sh` | Am 1. jeden Monats um 03:00 Uhr nachts | `0 3 1 * *` | Monatlich, selten genug für Stabilität |
### Profil `pi-home`

| Script | Wann genau | Cron-Ausdruck | Warum diese Zeit |
|--------|-----------|---------------|-----------------|
| `health-check.sh` | Alle 5 Minuten, rund um die Uhr | `*/5 * * * *` | Schnelle Reaktion bei Container-Ausfall |
| `monitor.sh` | Alle 15 Minuten, rund um die Uhr | `*/15 * * * *` | Ressourcenüberwachung |
| `backup-home.sh` | Täglich um 02:00 Uhr nachts | `0 2 * * *` | Alle Dienste konsistent sichern |
| `cleanup.sh` | Jeden Sonntag um 04:00 Uhr nachts | `0 4 * * 0` | Wöchentlich aufräumen |
| `sd-health.sh` | Jeden Montag um 06:00 Uhr früh | `0 6 * * 1` | Wöchentlicher SD-Bericht |
| `update.sh` | Am 1. jeden Monats um 03:00 Uhr nachts | `0 3 1 * *` | Monatliche Updates |


Als Crontab-Einträge:
```
*/5  * * * *  /home/pi/pi-admin/health-check.sh >> /home/pi/pi-admin/logs/health-check.log 2>&1
*/15 * * * *  /home/pi/pi-admin/monitor.sh >> /home/pi/pi-admin/logs/monitor.log 2>&1
0    2 * * *  /home/pi/pi-admin/backup-adguard.sh >> /home/pi/pi-admin/logs/backup-adguard.log 2>&1
0    4 * * 0  sudo /home/pi/pi-admin/cleanup.sh >> /home/pi/pi-admin/logs/cleanup.log 2>&1
0    6 * * 1  /home/pi/pi-admin/sd-health.sh >> /home/pi/pi-admin/logs/sd-health.log 2>&1
0    3 1 * *  /home/pi/pi-admin/update.sh >> /home/pi/pi-admin/logs/update.log 2>&1
```

---

## Cron-Syntax Kurzreferenz

```
*  *  *  *  *   Befehl
│  │  │  │  └── Wochentag (0=So, 1=Mo, ..., 7=So)
│  │  │  └───── Monat (1-12)
│  │  └──────── Tag (1-31)
│  └─────────── Stunde (0-23)
└───────────── Minute (0-59)

*/15  = alle 15 Minuten
0 4   = um 04:00 Uhr
0 4 * * 0  = Sonntags um 04:00 Uhr
0 3 1 * *  = Am 1. jedes Monats um 03:00 Uhr
```

---

## Job anpassen

```bash
crontab -e
```

Beispiel – Backup statt um 02:00 um 03:30 ausführen:
```bash
# Vorher:
0 2 * * *  /home/pi/pi-admin/backup-adguard.sh ...
# Nachher:
30 3 * * *  /home/pi/pi-admin/backup-adguard.sh ...
```

---

## Job manuell auslösen

Zum Testen jeden Job direkt aufrufen:

```bash
bash ~/pi-admin/health-check.sh
bash ~/pi-admin/monitor.sh
bash ~/pi-admin/backup-adguard.sh
sudo bash ~/pi-admin/cleanup.sh       # braucht sudo
bash ~/pi-admin/sd-health.sh
bash ~/pi-admin/update.sh
```

Ausgabe live mitverfolgen:
```bash
bash ~/pi-admin/monitor.sh && tail -20 ~/pi-admin/logs/monitor.log
```

---

## Logs prüfen

Jeder Job schreibt in eine eigene Logdatei unter `~/pi-admin/logs/`:

```bash
# Alle Logs auf einen Blick:
ls -lht ~/pi-admin/logs/

# Einzelne Logs:
tail -30 ~/pi-admin/logs/health-check.log
tail -30 ~/pi-admin/logs/monitor.log
tail -30 ~/pi-admin/logs/backup-adguard.log
tail -30 ~/pi-admin/logs/cleanup.log
tail -30 ~/pi-admin/logs/sd-health.log
tail -30 ~/pi-admin/logs/update.log

# Live mitlesen:
tail -f ~/pi-admin/logs/health-check.log
```

Logs werden automatisch nach `LOG_MAX_AGE_DAYS` (Standard: 60 Tage)
durch `cleanup.sh` gelöscht.

---

## Cron-Jobs nach Bootstrap prüfen

Nach einem frischen Setup prüfen ob alle Jobs angelegt wurden:

```bash
crontab -l | grep pi-admin
# Erwartet: 6 Zeilen
crontab -l | grep pi-admin | wc -l
```

Falls Jobs fehlen – Bootstrap erneut ausführen, er ist idempotent:
```bash
cd ~/pi-infra && git pull
sudo bash bootstrap.sh pi-dns
```

---

## Job deaktivieren

Zeile in der Crontab mit `#` auskommentieren:
```bash
crontab -e
# Zeile mit # am Anfang deaktivieren:
# */15 * * * *  /home/pi/pi-admin/monitor.sh ...
```