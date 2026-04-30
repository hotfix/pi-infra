# pi-infra

Automatisiertes Setup für Raspberry Pi – Infrastructure as Code.

## Schnellstart (frischer Pi)

```bash
bash <(curl -s https://codeberg.org/DEIN_USER/pi-infra/raw/branch/main/bootstrap.sh)
```

Das Script fragt welches Profil du willst und richtet alles automatisch ein.

## Profile

| Profil | Inhalt |
|--------|--------|
| `pi-dns` | AdGuard Home, Dockge, pi-admin Scripts |
| `pi-media` | Jellyfin, Dockge, pi-admin Scripts |
| `pi-home` | Home Assistant, Dockge, pi-admin Scripts |

Eigenes Profil anlegen: `profiles/MEIN_PROFIL/profile.sh` (siehe bestehende als Vorlage).

## Repo-Struktur

```
pi-infra/
├── bootstrap.sh               # Einstiegspunkt
├── .env.example               # Vorlage (sicher für Git)
├── .gitignore
├── README.md
├── profiles/
│   ├── pi-dns/
│   │   ├── profile.sh         # DNS-Pi Setup-Logik
│   │   └── docker/
│   │       └── adguard/
│   │           └── compose.yml
│   ├── pi-media/
│   │   ├── profile.sh
│   │   └── docker/
│   │       └── jellyfin/
│   │           └── compose.yml
│   └── pi-home/
│       ├── profile.sh
│       └── docker/
│           └── ...
└── shared/
    ├── scripts/               # Gemeinsame Scripts (alle Profile)
    │   ├── telegram_notify.sh
    │   ├── monitor.sh
    │   ├── health_check.sh
    │   ├── cleanup.sh
    │   ├── update.sh
    │   └── sd_health.sh
    └── docker/                # Stacks die alle Profile nutzen
        └── dockge/
            └── compose.yml
```

## Compose Files verwalten

Alle `compose.yml` liegen versioniert im Repo – nie direkt auf dem Pi bearbeiten.

Das `profile.sh` kopiert beim Setup automatisch:
- `profiles/PROFIL/docker/STACK/compose.yml` → `~/docker/STACK/compose.yml`
- `shared/docker/STACK/compose.yml` → `~/docker/STACK/compose.yml` (für alle Profile)

Neuen Stack hinzufügen:
```bash
mkdir -p profiles/pi-dns/docker/mein-stack
nano profiles/pi-dns/docker/mein-stack/compose.yml
git add . && git commit -m "Add mein-stack" && git push
# Auf dem Pi:
cd ~/pi-infra && git pull && sudo bash bootstrap.sh pi-dns
```

## Secrets verwalten

Die `.env` liegt **nicht** im Repo – nur `.env.example` als Vorlage.
`bootstrap.sh` fragt beim ersten Setup nach Token und Chat-ID.

```bash
# Manuell bearbeiten:
nano ~/pi-admin/.env
```

## Repo aktualisieren

```bash
cd ~/pi-infra && git pull
bash bootstrap.sh pi-dns   # Profil neu anwenden
```

Idempotent: Bereits laufende Container werden nicht neu gestartet.