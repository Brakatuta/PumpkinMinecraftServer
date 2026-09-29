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

## Quick Start (Recommended: Decoupled Setup)

To keep your personal configuration, persistent world data, and Compose files completely isolated from git updates (preventing any `git pull` merge conflicts), use the included `quickstart.sh` script:

### 1. Clone & Initialize
```bash
git clone https://github.com/Brakatuta/PumpkinMinecraftServer.git
cd PumpkinMinecraftServer

# Run quickstart to deploy docker-compose.yml and .env to the parent directory
./quickstart.sh
```

This creates the following clean directory structure:
```text
SurvivalProject/
├── docker-compose.yml      <-- Active Compose file (points to ./PumpkinMinecraftServer)
├── .env                    <-- Your custom configuration settings
├── server_data/            <-- Persistent world, configs, and logs
└── PumpkinMinecraftServer/ <-- Cloned git repository (kept 100% clean)
```

### 2. Configure & Start
```bash
# Move to your project root
cd ..

# (Optional) Customize server settings, RAM, player count, etc.
nano .env

# Start server in background
docker compose up -d --build
# Or with Podman:
podman compose up -d --build
```

### 3. View Live Logs & Stop
```bash
# View live logs:
docker compose logs -f

# Stop the server:
docker compose down
```

### 4. Updating the Server (Conflict-Free!)
Because you never edit any file inside `PumpkinMinecraftServer/`, updating is seamless:
```bash
cd PumpkinMinecraftServer
git pull
cd ..
docker compose up -d --build
```

> [!TIP]
> **Already experiencing a `git pull` conflict on `docker-compose.yml`?**
> Run:
> ```bash
> git restore docker-compose.yml
> git pull
> ./quickstart.sh
> ```

---

## Configuration (`.env` or `docker-compose.yml`)

Adjust your server settings in your `.env` file (copied from `.env.example`). All environment variables automatically fall back to sensible defaults:

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
      - RAM_LIMIT=${RAM_LIMIT:-4g}
    mem_limit: ${RAM_LIMIT:-4g}
    mem_reservation: ${RAM_RESERVATION:-1g}
    volumes:
      - ./server_data:/data:Z
    stdin_open: true
    tty: true
```

### RAM / Memory Limits
Because Pumpkin is compiled directly to native machine code in **Rust** (unlike vanilla Java servers which run inside a Java Virtual Machine), there are no `-Xmx` or `-Xms` Java flags. Memory is managed natively with extreme efficiency.

You can configure the RAM limits for the container using `RAM_LIMIT` and `RAM_RESERVATION` in `.env` or `docker-compose.yml`:
- `RAM_LIMIT`: Hard memory ceiling for the container (e.g. `2g`, `4g`, `8g`, `16g`).
- `RAM_RESERVATION`: Soft memory guarantee (e.g. `1g`, `2g`).

When using `docker run` or `podman run`:
```bash
docker run -d --name pumpkin-server \
  --network host \
  -m 4g --memory-reservation 1g \
  -v ./server_data:/data:Z \
  pumpkin-minecraft-server:latest
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
