# Pumpkin Minecraft Server (Rust-based) Docker Container

Ein vollautomatischer Docker/Podman-Container für den in **Rust** geschriebenen Hochleistungs-Minecraft-Server **[Pumpkin](https://github.com/Pumpkin-MC/Pumpkin)**.

## Features

- **Automatischer Versions-Download**: Übergib einfach den gewünschten Minecraft-Versionscode (z. B. `VERSION=26.2`), und der Container lädt automatisch die passende native Linux-Binary von GitHub herunter.
- **Automatische Update-Prüfung**: Bei jedem Container-Start wird auf GitHub geprüft, ob ein neueres Release für die gewählte Version vorliegt.
- **Vollständig konfigurierbar via Umgebungsvariablen**:
  - `MAX_PLAYERS` (Standard: `10`)
  - `VIEW_DISTANCE` (Standard: `32` Chunks)
  - `SIMULATION_DISTANCE` (Standard: `16` Chunks)
  - `SEED` (Welt-Seed, optional)
  - `LAN_BROADCAST` (Standard: `true` – automatisches Erscheinen in der lokalen Serverliste)
  - `GAMEMODE` (Standard: `Survival`)
  - `DIFFICULTY` (Standard: `Normal`)
  - `MOTD` (Servername / Beschreibung)
  - `ONLINE_MODE` (Standard: `false` – erlaubt lokale/Offline-Accounts wie `Muharica`)
  - `OP_ACCOUNT` (Standard: `Muharica` – wird automatisch als Admin mit Level 4 eingetragen)
- **Persistente Datenhaltung**: Alle Konfigurationen, Welten, Spielerdaten und Logs werden im gemounteten Host-Verzeichnis `./server_data` gesichert.
- **Logs**: Alle Server-Ausgaben werden live über die Container-Logs (`docker logs -f pumpkin-server`) sowie in `./server_data/logs/latest.log` gespeichert.

---

## Schnellstart

### 1. Repository klonen
```bash
git clone https://github.com/Brakatuta/PumpkinMinecraftServer.git
cd PumpkinMinecraftServer
```

### 2. Server starten mit Docker Compose oder Podman Compose
```bash
docker compose up -d --build
# oder mit Podman:
podman compose up -d --build
```

### 3. Server-Logs ansehen
```bash
docker compose logs -f
# oder mit Podman:
podman compose logs -f
```

### 4. Server stoppen
```bash
docker compose down
```

---

## Konfiguration (`docker-compose.yml`)

Alle Einstellungen können direkt in der `docker-compose.yml` (oder über eine `.env`-Datei) angepasst werden:

```yaml
services:
  pumpkin:
    build: .
    image: pumpkin-minecraft-server:latest
    container_name: pumpkin-server
    restart: unless-stopped
    network_mode: host # Empfohlen für automatische LAN-Erkennung (Multicast)
    environment:
      - VERSION=26.2
      - MAX_PLAYERS=10
      - VIEW_DISTANCE=32
      - SIMULATION_DISTANCE=16
      - SEED=
      - LAN_BROADCAST=true
      - GAMEMODE=Survival
      - DIFFICULTY=Normal
      - MOTD=A blazingly fast Pumpkin Minecraft server!
      - ONLINE_MODE=false
      - DEFAULT_OP_LEVEL=4
      - OP_ACCOUNT=Muharica
      - AUTO_UPDATE=true
    volumes:
      - ./server_data:/data
    stdin_open: true
    tty: true
```

### Netzwerk & Ports
* **`network_mode: host` (Standard & Empfohlen)**:
  Ermöglicht dem Minecraft-Client im selben Netzwerk, den Server automatisch unter *"LAN-Welten"* in der Multiplayer-Liste zu sehen (UDP Multicast `224.0.2.60:4445`).
* **Klassisches Port-Mapping (Bridge-Modus)**:
  Falls du Bridge-Networking bevorzugst, kommentiere `network_mode: host` aus und aktiviere die Ports:
  ```yaml
  ports:
    - "25565:25565"       # Java Edition
    - "19132:19132/udp"   # Bedrock Edition
    - "19133:19133/udp"   # Bedrock IPv6
    - "4445:4445/udp"     # LAN Broadcast
  ```

---

## Manuelle Standalone-Nutzung (ohne Docker)

Falls du den Server direkt auf der Linux-Hostmaschine ohne Container laufen lassen möchtest:
- **Start**: `./start.sh`
- **Stop**: `./stop.sh`
