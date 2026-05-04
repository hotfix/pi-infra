# pi-infra

Automatisiertes Setup für Raspberry Pi – Infrastructure as Code.

Getestet auf Raspberry Pi 3B mit Raspberry Pi OS Lite.

---

## Schnellstart

```bash
curl -s https://codeberg.org/hotfix/pi-infra/raw/branch/main/bootstrap.sh | sudo bash
```

Das Script fragt welches Profil du willst und richtet alles automatisch ein –
Docker, Container, Scripts, Cron-Jobs und Telegram.

---

## Profile

| Profil | Inhalt |
|--------|--------|
| `pi-dns` | AdGuard Home, Dockge, pi-admin Scripts |
| `pi-media` | Jellyfin, Dockge, pi-admin Scripts |
| `pi-home` | Home Assistant, Dockge, pi-admin Scripts |

---

## Repo-Struktur

```
pi-infra/
├── bootstrap.sh               # Einstiegspunkt
├── .env.example               # Vorlage (sicher für Git)
├── profiles/
│   ├── pi-dns/
│   │   ├── profile.sh
│   │   └── docker/
│   │       └── adguard/
│   │           └── compose.yml
│   └── pi-media/
│       ├── profile.sh
│       └── docker/
│           └── jellyfin/
│               └── compose.yml
├── shared/
│   ├── scripts/               # monitor, cleanup, update, ...
│   └── docker/
│       └── dockge/
│           └── compose.yml
└── docs/                      # Ausführliche Dokumentation
```

---

## Dokumentation

- [Telegram Bot einrichten](docs/telegram.md)
- [Profile & neues Profil anlegen](docs/profiles.md)
- [Docker & Compose Files verwalten](docs/docker.md)
- [Secrets & .env](docs/secrets.md)
- [Backup & NAS](docs/backup.md)
- [Cron-Jobs](docs/cron.md)
- [Windows Remote-Deploy](docs/windows-deploy.md)
- [Troubleshooting](docs/troubleshooting.md)

---

## Repo aktualisieren

```bash
cd ~/pi-infra && git pull
sudo bash bootstrap.sh pi-dns
```

Idempotent – bereits laufende Container werden nicht neu gestartet.