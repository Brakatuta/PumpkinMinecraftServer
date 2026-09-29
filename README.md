# Pumpkin Minecraft Server (Rust-based) Docker Container

A fully automated Docker/Podman container for the high-performance Minecraft server **[Pumpkin](https://github.com/Pumpkin-MC/Pumpkin)**, built entirely in **Rust**.

## Features

- **Automatic Version Downloads**: Provide your target Minecraft version code (e.g. `VERSION=26.2`), and the container automatically discovers and downloads the matching native Linux x86_64 binary directly from GitHub releases.
- **Automatic Update Checking**: Every time the container boots, it queries GitHub to ensure you are running the latest release for your selected version.
- **Fully Configurable via Environment Variables**:
  - `VERSION` (Default: `26.2`)
  - `MAX_PLAYERS` (Default: `10`)
  - `VIEW_DISTANCE` (Default: `32` chunks)
  - `SIMULATION_DISTANCE` (Default: `16` chunks)
  - `SEED` (Optional custom world generation seed)
  - `LAN_BROADCAST` (Default: `true` — server automatically appears in local LAN world lists)
  - `GAMEMODE` (Default: `Survival`)
  - `DIFFICULTY` (Default: `Normal`)
  - `MOTD` (Server message / display name)
  - `ONLINE_MODE` (Default: `false` — permits offline/LAN players without Mojang session verification)
  - `OP_ACCOUNT` (Default: `SOME_USER` — comma-separated usernames supported; automatically resolves and injects their correct Mojang or offline UUIDs into `data/ops.json`)
  - `SERVER_ICON` (Default: `server.png` — 64x64 PNG server icon; automatically deployed if missing)
  - `DEFAULT_OP_LEVEL` (Default: `4`)
  - `AUTO_UPDATE` (Default: `true`)
- **Persistent Data Storage**: All configurations, worlds, player data, and logs are cleanly mounted and preserved on the host in `./server_data`.
- **Live Logging**: Console output is accessible live via container logs (`docker logs -f pumpkin-server`) and saved locally to `./server_data/logs/latest.log`.

---

## Quick Start

### 1. Clone Repository
```bash
git clone https://github.com/Brakatuta/PumpkinMinecraftServer.git
cd PumpkinMinecraftServer
```

### 2. Launch with Docker Compose or Podman Compose
```bash
docker compose up -d --build
# Or with Podman:
podman compose up -d --build
```

### 3. View Live Logs
```bash
docker compose logs -f
# Or with Podman:
podman compose logs -f
```

### 4. Stop the Server
```bash
docker compose down
```

---

## Configuration (`docker-compose.yml`)

Adjust any server setting directly in `docker-compose.yml` or create a `.env` file from `.env.example`:

```yaml
services:
  pumpkin:
    build: .
    image: pumpkin-minecraft-server:latest
    container_name: pumpkin-server
    restart: unless-stopped
    network_mode: host # Recommended for auto-discovery across your local home network
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
      - OP_ACCOUNT=SOME_USER
      - SERVER_ICON=server.png
      - AUTO_UPDATE=true
    volumes:
      - ./server_data:/data
    stdin_open: true
    tty: true
```

### Networking & Port Options
* **`network_mode: host` (Default & Recommended)**:
  Allows Minecraft clients on your local network to discover the server automatically under *"LAN Worlds"* in the Multiplayer server list via UDP multicast (`224.0.2.60:4445`).
* **Bridge Mode Port Mapping**:
  If you prefer standard Docker bridge networking, comment out `network_mode: host` and uncomment the port mappings:
  ```yaml
  ports:
    - "25565:25565"       # Minecraft Java Edition
    - "19132:19132/udp"   # Minecraft Bedrock Edition
    - "19133:19133/udp"   # Bedrock IPv6 status
    - "4445:4445/udp"     # Minecraft LAN Broadcast
  ```

---

## Standalone Host Usage (Without Containers)

If you prefer to run the server directly on the host machine without Docker:
- **Start**: `./start.sh`
- **Stop**: `./stop.sh`
