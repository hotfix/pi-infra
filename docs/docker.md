# Docker & Compose Files verwalten

Alle `compose.yml` liegen versioniert im Repo – nie direkt auf dem Pi bearbeiten.
Änderungen immer über Git einspielen.

---

## Struktur

```
shared/docker/          # Stacks die ALLE Profile bekommen
└── dockge/
    └── compose.yml

profiles/pi-dns/docker/ # Stacks nur für dieses Profil
└── adguard/
    └── compose.yml
```

Beim Bootstrap kopiert `profile.sh` automatisch alle `compose.yml`
an die richtige Stelle auf dem Pi:

```
~/docker/adguard/compose.yml
~/docker/dockge/compose.yml
```

---

## Neuen Stack hinzufügen

```bash
# Im Repo (auf deinem Rechner):
mkdir -p profiles/pi-dns/docker/mein-stack
nano profiles/pi-dns/docker/mein-stack/compose.yml

git add .
git commit -m "feat(pi-dns): add mein-stack"
git push

# Auf dem Pi einspielen:
cd ~/pi-infra && git pull
sudo bash bootstrap.sh pi-dns
```

Stack für alle Profile (shared):

```bash
mkdir -p shared/docker/mein-stack
nano shared/docker/mein-stack/compose.yml
```

---

## Compose File aktualisieren

```bash
# Änderung im Repo committen & pushen, dann auf dem Pi:
cd ~/pi-infra && git pull
sudo bash bootstrap.sh pi-dns

# Falls der Container neu gestartet werden muss:
cd ~/docker/mein-stack && docker compose up -d
```

---

## Dockge als UI

Alle Stacks unter `~/docker/` sind automatisch in Dockge sichtbar.

```
http://PI_IP:5001
```

Über Dockge kannst du Container starten, stoppen, Logs einsehen
und `compose.yml` im Browser bearbeiten – für schnelle Anpassungen
direkt auf dem Pi ohne SSH.

> **Hinweis:** Änderungen über die Dockge-UI werden beim nächsten
> `bootstrap.sh` durch die Repo-Version überschrieben. Dauerhafte
> Änderungen immer im Repo pflegen.

---

## Nützliche Docker-Befehle

```bash
# Alle Container + Status
docker ps -a

# Logs eines Containers
docker logs adguard -f

# Stack neu starten
cd ~/docker/adguard && docker compose restart

# Stack komplett neu aufbauen (z.B. nach Image-Update)
cd ~/docker/adguard && docker compose pull && docker compose up -d

# Speicher freigeben (ungenutzte Images, Volumes)
docker system prune -f
```