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
SERVER_ICON="${SERVER_ICON:-server.png}"

DATA_DIR="/data"
BIN_PATH="/usr/local/bin/pumpkin"
VERSION_FILE="$DATA_DIR/.pumpkin_version"

cd "$DATA_DIR"
mkdir -p "$DATA_DIR/data" "$DATA_DIR/logs"

# --------------------------------------------------
# 1. Server Icon Setup
# --------------------------------------------------
if [ -n "$SERVER_ICON" ]; then
    if [ ! -f "$DATA_DIR/$SERVER_ICON" ] && [ -f "/defaults/$SERVER_ICON" ]; then
        echo "[Config] Deploying default server icon to $DATA_DIR/$SERVER_ICON..."
        cp "/defaults/$SERVER_ICON" "$DATA_DIR/$SERVER_ICON"
    fi
fi

# --------------------------------------------------
# 2. Check & Fetch Pumpkin binary for Minecraft VERSION
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
# 3. Initialize default configuration if missing
# --------------------------------------------------
if [ ! -f "$DATA_DIR/pumpkin.toml" ]; then
    echo "[Config] Initializing default pumpkin.toml..."
    "$BIN_PATH" &
    INIT_PID=$!
    sleep 2
    kill -TERM "$INIT_PID" 2>/dev/null || true
    wait "$INIT_PID" 2>/dev/null || true
fi

# --------------------------------------------------
# 4. Synchronize environment variables into pumpkin.toml
# --------------------------------------------------
echo "[Config] Applying server settings to pumpkin.toml..."
python3 - <<EOF
import re, os

config_path = "$DATA_DIR/pumpkin.toml"
try:
    with open(config_path, "r", encoding="utf-8") as f:
        content = f.read()
except Exception as e:
    print(f"Could not read {config_path}: {e}")
    content = ""

def set_top_level(key, value, is_string=False):
    global content
    formatted = f'"{value}"' if is_string else str(value).lower()
    pattern = rf'^{re.escape(key)}\s*=.*$'
    if re.search(pattern, content, flags=re.MULTILINE):
        content = re.sub(pattern, f'{key} = {formatted}', content, flags=re.MULTILINE)
    else:
        content = f'{key} = {formatted}\n' + content

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

# Favicon / Server Icon
icon_file = "$SERVER_ICON"
if icon_file and os.path.isfile(os.path.join("$DATA_DIR", icon_file)):
    set_top_level("use_favicon", "true")
    set_top_level("favicon_path", icon_file, is_string=True)
elif icon_file:
    set_top_level("use_favicon", "true")
    set_top_level("favicon_path", icon_file, is_string=True)
else:
    set_top_level("use_favicon", "false")

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
# 5. Synchronize Operator List (ops.json) with exact UUIDs
# --------------------------------------------------
OPS_FILE="$DATA_DIR/data/ops.json"
echo "[Config] Synchronizing operators in ${OPS_FILE}..."
python3 - <<EOF
import json, hashlib, uuid, os, urllib.request

ops_file = "${OPS_FILE}"
raw_ops_input = "${OP_ACCOUNT}".strip()
online_mode = "${ONLINE_MODE}".lower() in ["true", "1", "yes"]
default_level = int("${DEFAULT_OP_LEVEL}")

existing_ops = []
if os.path.exists(ops_file):
    try:
        with open(ops_file, "r", encoding="utf-8") as f:
            data = json.load(f)
            if isinstance(data, list):
                existing_ops = data
    except Exception as e:
        print(f"[Config] Note: Could not parse existing {ops_file} ({e}), creating fresh list.")

def get_offline_uuid(name):
    content = ('OfflinePlayer:' + name).encode('utf-8')
    md5 = bytearray(hashlib.md5(content).digest())
    md5[6] = (md5[6] & 0x0f) | 0x30 # version 3
    md5[8] = (md5[8] & 0x3f) | 0x80 # variant RFC 4122
    return str(uuid.UUID(bytes=bytes(md5)))

def get_mojang_uuid(name):
    try:
        url = f"https://api.mojang.com/users/profiles/minecraft/{name}"
        req = urllib.request.Request(url, headers={"User-Agent": "Pumpkin-Server-Config"})
        with urllib.request.urlopen(req, timeout=3) as resp:
            if resp.status == 200:
                profile = json.loads(resp.read().decode("utf-8"))
                raw_id = profile.get("id")
                if raw_id:
                    return str(uuid.UUID(raw_id)), profile.get("name", name)
    except Exception:
        pass
    return None, name

usernames = [u.strip() for u in raw_ops_input.split(",") if u.strip()]

for user in usernames:
    resolved_name = user
    resolved_uuid = None
    uuid_type = "offline"

    if online_mode:
        mojang_id, correct_name = get_mojang_uuid(user)
        if mojang_id:
            resolved_uuid = mojang_id
            resolved_name = correct_name
            uuid_type = "mojang"
        else:
            resolved_uuid = get_offline_uuid(user)
    else:
        resolved_uuid = get_offline_uuid(user)

    # Check if already present by UUID or name
    matched = False
    for op in existing_ops:
        if op.get("uuid") == resolved_uuid or op.get("name", "").lower() == resolved_name.lower():
            op["uuid"] = resolved_uuid
            op["name"] = resolved_name
            op["level"] = default_level
            op["bypassesPlayerLimit"] = op.get("bypassesPlayerLimit", False)
            matched = True
            print(f"[Config] Updated operator '{resolved_name}' (UUID: {resolved_uuid}, Type: {uuid_type}, Level: {default_level})")
            break

    if not matched:
        existing_ops.append({
            "uuid": resolved_uuid,
            "name": resolved_name,
            "level": default_level,
            "bypassesPlayerLimit": False
        })
        print(f"[Config] Added operator '{resolved_name}' (UUID: {resolved_uuid}, Type: {uuid_type}, Level: {default_level})")

with open(ops_file, "w", encoding="utf-8") as f:
    json.dump(existing_ops, f, indent=2)

print(f"[Config] Operator list successfully synchronized ({len(existing_ops)} operators).")
EOF

# --------------------------------------------------
# 6. Launch Pumpkin with signal handling & live logging
# --------------------------------------------------
echo "=================================================="
echo " Starting Pumpkin Server (MC ${VERSION})          "
echo " Max Players:       ${MAX_PLAYERS}"
echo " View Distance:     ${VIEW_DISTANCE}"
echo " Simulation Dist:   ${SIMULATION_DISTANCE}"
echo " Gamemode:          ${GAMEMODE}"
echo " Difficulty:        ${DIFFICULTY}"
echo " LAN Broadcast:     ${LAN_BROADCAST}"
echo " Server Icon:       ${SERVER_ICON}"
echo " MOTD:              ${MOTD}"
echo " Online Mode:       ${ONLINE_MODE}"
echo "=================================================="

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
