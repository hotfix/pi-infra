# Backup

---

## Was wird gesichert

### AdGuard Home (`backup_adguard.sh`)

| Verzeichnis | Inhalt |
|-------------|--------|
| `~/docker/adguard/conf/` | Einstellungen, Filterlisten, DNS-Regeln, Blocklisten |
| `~/docker/adguard/data/` | Statistiken, Datenbank |

Das Script stoppt AdGuard kurz während des Backups damit die Dateien konsistent sind,
und startet ihn danach automatisch wieder. Die Downtime beträgt nur wenige Sekunden.

Backups landen unter `~/backup/adguard/` als komprimierte `.tar.gz` Dateien:
```
~/backup/adguard/
├── adguard_2026-04-30_02-00.tar.gz
├── adguard_2026-04-29_02-00.tar.gz
└── ...
```

Alte Backups werden automatisch nach `BACKUP_MAX_AGE_DAYS` (Standard: 30 Tage) gelöscht.

---

## Backup manuell ausführen

```bash
bash ~/pi-admin/backup_adguard.sh
# Ergebnis in ~/backup/adguard/ prüfen:
ls -lh ~/backup/adguard/
```

---

## Backup wiederherstellen

```bash
# Gewünschtes Backup auswählen:
ls ~/backup/adguard/

# AdGuard stoppen:
cd ~/docker/adguard && docker compose stop

# Backup entpacken:
cd ~/backup/adguard/
tar -xzf adguard_2026-04-30_02-00.tar.gz

# Dateien zurückspielen:
cp -r adguard_2026-04-30_02-00/conf/* ~/docker/adguard/conf/
cp -r adguard_2026-04-30_02-00/data/* ~/docker/adguard/data/

# AdGuard wieder starten:
cd ~/docker/adguard && docker compose up -d
```

---

## NAS-Transfer einrichten (QNAP)

Sobald du bereit bist Backups auf dein QNAP zu schieben,
in `~/pi-admin/.env` folgende Variablen setzen:

### Option A – rsync über SSH (empfohlen)

Sicherer als SMB, kein Passwort im Klartext.

```bash
# 1. SSH-Key für NAS generieren (einmalig):
ssh-keygen -t ed25519 -f ~/.ssh/id_rsa_nas -N ""

# 2. Public Key auf QNAP kopieren:
ssh-copy-id -i ~/.ssh/id_rsa_nas.pub admin@192.168.1.100
# Oder manuell in QNAP DSM: Systemsteuerung → SSH → authorized_keys

# 3. In .env eintragen:
NAS_ENABLED=true
NAS_METHOD=rsync
NAS_HOST=192.168.1.100
NAS_USER=admin
NAS_PATH=/share/backup/pi-dns
NAS_SSH_KEY=~/.ssh/id_rsa_nas
```

### Option B – SMB/Samba

```bash
# Paket installieren:
sudo apt-get install -y cifs-utils

# Credentials sicher ablegen (nicht in .env!):
cat > ~/.smbcredentials << EOF
username=admin
password=DEIN_QNAP_PASSWORT
EOF
chmod 600 ~/.smbcredentials

# In .env eintragen:
NAS_ENABLED=true
NAS_METHOD=smb
NAS_HOST=192.168.1.100
NAS_SHARE=backup          # Name der QNAP-Freigabe
NAS_PATH=/pi-dns          # Unterordner
```

### Transfer testen

```bash
# Backup mit NAS-Transfer manuell auslösen:
bash ~/pi-admin/backup_adguard.sh

# Log prüfen:
tail -30 ~/pi-admin/logs/backup_adguard.log
```

---

## Cron-Zeitplan

| Script | Zeit | Häufigkeit |
|--------|------|------------|
| `backup_adguard.sh` | 02:00 | täglich |

Zeitplan anpassen:
```bash
crontab -e
# Zeile mit backup_adguard.sh suchen und Zeit ändern
```