#!/usr/bin/env bash
set -eo pipefail

echo "=================================================="
echo "    Starting Pumpkin Minecraft Server Container   "
echo "=================================================="

# Environment variables & defaults
VERSION="${VERSION:-26.2}"
MAX_PLAYERS="${MAX_PLAYERS:-10}"
VIEW_DISTANCE="${VIEW_DISTANCE:-32}"
SIMULATION_DISTANCE="${SIMULATION_DISTANCE:-16}"
SEED="${SEED:-}"
LAN_BROADCAST="${LAN_BROADCAST:-true}"
GAMEMODE="${GAMEMODE:-Survival}"
DIFFICULTY="${DIFFICULTY:-Normal}"
MOTD="${MOTD:-A blazingly fast Pumpkin Minecraft server!}"
ONLINE_MODE="${ONLINE_MODE:-false}"
DEFAULT_OP_LEVEL="${DEFAULT_OP_LEVEL:-4}"
AUTO_UPDATE="${AUTO_UPDATE:-true}"
OP_ACCOUNT="${OP_ACCOUNT:-SOME_USER}"

DATA_DIR="/data"
BIN_PATH="/usr/local/bin/pumpkin"
VERSION_FILE="$DATA_DIR/.pumpkin_version"

cd "$DATA_DIR"
mkdir -p "$DATA_DIR/data" "$DATA_DIR/logs"

# --------------------------------------------------
# 1. Check & Fetch Pumpkin binary for Minecraft VERSION
# --------------------------------------------------
fetch_latest_release() {
    echo "[Updater] Checking GitHub for Pumpkin release matching Minecraft ${VERSION}..."
    local releases_json
    releases_json=$(curl -sSL "https://api.github.com/repos/Pumpkin-MC/Pumpkin/releases")

    # Look for release matching the version (e.g. "+26.2" or "26.2")
    local matched_release
    matched_release=$(echo "$releases_json" | jq -c --arg ver "$VERSION" '
        [ .[] | select((.tag_name | test("\\+" + $ver + "($|-)")) or (.name | test($ver))) ] | first
    ')

    if [ -z "$matched_release" ] || [ "$matched_release" = "null" ]; then
        echo "[Updater] Warning: No specific tag found matching '+${VERSION}'. Falling back to latest release."
        matched_release=$(echo "$releases_json" | jq -c 'first')
    fi

    local tag_name
    tag_name=$(echo "$matched_release" | jq -r '.tag_name')
    echo "[Updater] Found release tag: ${tag_name}"

    local current_installed=""
    if [ -f "$VERSION_FILE" ]; then
        current_installed=$(cat "$VERSION_FILE")
    fi

    if [ ! -x "$BIN_PATH" ] || [ "$current_installed" != "$tag_name" ] || [ "$AUTO_UPDATE" = "force" ]; then
        echo "[Updater] Downloading binary for release ${tag_name}..."
        local download_url
        download_url=$(echo "$matched_release" | jq -r '
            .assets[] | select(.name == "pumpkin-X64-Linux") | .browser_download_url
        ')

        if [ -z "$download_url" ] || [ "$download_url" = "null" ]; then
            echo "[Updater] Error: pumpkin-X64-Linux asset not found in release ${tag_name}!"
            exit 1
        fi

        curl -sSL -o "$BIN_PATH" "$download_url"
        chmod +x "$BIN_PATH"
        echo "$tag_name" > "$VERSION_FILE"
        echo "[Updater] Successfully installed Pumpkin (${tag_name}) to ${BIN_PATH}."
    else
        echo "[Updater] Pumpkin binary is up to date (${tag_name})."
    fi
}

if [ "$AUTO_UPDATE" = "true" ] || [ "$AUTO_UPDATE" = "force" ] || [ ! -x "$BIN_PATH" ]; then
    fetch_latest_release
fi

if [ ! -x "$BIN_PATH" ]; then
    echo "[Error] No executable Pumpkin binary found at ${BIN_PATH}!"
    exit 1
fi

# --------------------------------------------------
# 2. Initialize default configuration if missing
# --------------------------------------------------
if [ ! -f "$DATA_DIR/pumpkin.toml" ]; then
    echo "[Config] Initializing default pumpkin.toml..."
    # Run briefly in background to let Pumpkin write initial configs
    "$BIN_PATH" &
    INIT_PID=$!
    sleep 2
    kill -TERM "$INIT_PID" 2>/dev/null || true
    wait "$INIT_PID" 2>/dev/null || true
fi

# --------------------------------------------------
# 3. Synchronize environment variables into pumpkin.toml
# --------------------------------------------------
echo "[Config] Applying server settings to pumpkin.toml..."
python3 - <<EOF
import re

config_path = "$DATA_DIR/pumpkin.toml"
try:
    with open(config_path, "r", encoding="utf-8") as f:
        content = f.read()
except Exception as e:
    print(f"Could not read {config_path}: {e}")
    content = ""

# Updates top-level scalar values
def set_top_level(key, value, is_string=False):
    global content
    formatted = f'"{value}"' if is_string else str(value).lower()
    pattern = rf'^{re.escape(key)}\s*=.*$'
    if re.search(pattern, content, flags=re.MULTILINE):
        content = re.sub(pattern, f'{key} = {formatted}', content, flags=re.MULTILINE)
    else:
        content = f'{key} = {formatted}\n' + content

# Updates table values
def set_section_key(section, key, value, is_string=False):
    global content
    formatted = f'"{value}"' if is_string else (f'"{value}"' if isinstance(value, str) and not value in ["true", "false"] else str(value).lower())
    
    sec_pattern = rf'(\[{re.escape(section)}\][^\[]*)'
    m = re.search(sec_pattern, content)
    if m:
        sec_block = m.group(1)
        k_pattern = rf'^{re.escape(key)}\s*=.*$'
        if re.search(k_pattern, sec_block, flags=re.MULTILINE):
            new_block = re.sub(k_pattern, f'{key} = {formatted}', sec_block, flags=re.MULTILINE)
        else:
            new_block = sec_block.rstrip() + f'\n{key} = {formatted}\n'
        content = content[:m.start()] + new_block + content[m.end():]
    else:
        content += f'\n[{section}]\n{key} = {formatted}\n'

seed_val = "$SEED"
if seed_val:
    set_top_level("seed", seed_val, is_string=True)

set_top_level("default_gamemode", "$GAMEMODE", is_string=True)
set_top_level("default_difficulty", "$DIFFICULTY", is_string=True)

# LAN broadcast
lan_enabled = "$LAN_BROADCAST".lower() in ["true", "1", "yes"]
set_section_key("networking.lan_broadcast", "enabled", "true" if lan_enabled else "false")

# Networking Java
set_section_key("networking.java", "max_players", "$MAX_PLAYERS")
set_section_key("networking.java", "view_distance", "$VIEW_DISTANCE")
set_section_key("networking.java", "simulation_distance", "$SIMULATION_DISTANCE")
set_section_key("networking.java", "motd", "$MOTD", is_string=True)
set_section_key("networking.java", "online_mode", "$ONLINE_MODE".lower())

# Networking Bedrock
set_section_key("networking.bedrock", "max_players", "$MAX_PLAYERS")
set_section_key("networking.bedrock", "view_distance", "$VIEW_DISTANCE")
set_section_key("networking.bedrock", "simulation_distance", "$SIMULATION_DISTANCE")
set_section_key("networking.bedrock", "motd", "$MOTD", is_string=True)
set_section_key("networking.bedrock", "online_mode", "$ONLINE_MODE".lower())

# Commands
set_section_key("commands", "default_op_level", "$DEFAULT_OP_LEVEL")

with open(config_path, "w", encoding="utf-8") as f:
    f.write(content)
print("[Config] Settings successfully written to pumpkin.toml.")
EOF

# --------------------------------------------------
# 4. Initialize Operator list (ops.json) if needed
# --------------------------------------------------
OPS_FILE="$DATA_DIR/data/ops.json"
if [ ! -f "$OPS_FILE" ] || [ ! -s "$OPS_FILE" ] || [ "$(cat "$OPS_FILE" 2>/dev/null)" = "[]" ]; then
    echo "[Config] Initializing $OPS_FILE with operator account '${OP_ACCOUNT}'..."
    python3 - <<EOF
import json, hashlib, uuid

def offline_uuid(name):
    content = ('OfflinePlayer:' + name).encode('utf-8')
    md5 = bytearray(hashlib.md5(content).digest())
    md5[6] = (md5[6] & 0x0f) | 0x30
    md5[8] = (md5[8] & 0x3f) | 0x80
    return str(uuid.UUID(bytes=bytes(md5)))

op_name = "${OP_ACCOUNT}"
op_uuid = offline_uuid(op_name)

ops_data = [
    {
        "uuid": op_uuid,
        "name": op_name,
        "level": int("${DEFAULT_OP_LEVEL}"),
        "bypassesPlayerLimit": False
    }
]

with open("${OPS_FILE}", "w", encoding="utf-8") as f:
    json.dump(ops_data, f, indent=2)
EOF
fi

# --------------------------------------------------
# 5. Launch Pumpkin with signal handling & tee logging
# --------------------------------------------------
echo "=================================================="
echo " Starting Pumpkin Server (MC ${VERSION})          "
echo " Max Players:       ${MAX_PLAYERS}"
echo " View Distance:     ${VIEW_DISTANCE}"
echo " Simulation Dist:   ${SIMULATION_DISTANCE}"
echo " Gamemode:          ${GAMEMODE}"
echo " Difficulty:        ${DIFFICULTY}"
echo " LAN Broadcast:     ${LAN_BROADCAST}"
echo " MOTD:              ${MOTD}"
echo " Online Mode:       ${ONLINE_MODE}"
echo "=================================================="

# Forward termination signals gracefully
cleanup() {
    echo "[Server] Received stop signal. Shutting down Pumpkin..."
    if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill -TERM "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    echo "[Server] Stopped cleanly."
    exit 0
}
trap cleanup INT TERM

"$BIN_PATH" &
SERVER_PID=$!
wait "$SERVER_PID" 2>/dev/null || true
