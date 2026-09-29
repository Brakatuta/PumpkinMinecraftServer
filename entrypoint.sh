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
OP_ACCOUNTS="${OP_ACCOUNTS:-${OP_ACCOUNT:-}}"
SERVER_ICON="${SERVER_ICON:-server.png}"

DATA_DIR="/data"
BIN_DIR="$DATA_DIR/bin"
BIN_PATH="$BIN_DIR/pumpkin"
VERSION_FILE="$DATA_DIR/.pumpkin_version"

cd "$DATA_DIR"
mkdir -p "$DATA_DIR/data" "$DATA_DIR/logs" "$BIN_DIR"

# --------------------------------------------------
# 1. Initialize default templates if missing
# --------------------------------------------------
if [ -n "$SERVER_ICON" ]; then
    if [ ! -f "$DATA_DIR/$SERVER_ICON" ] && [ -f "/defaults/$SERVER_ICON" ]; then
        echo "[Config] Deploying default server icon to $DATA_DIR/$SERVER_ICON..."
        cp "/defaults/$SERVER_ICON" "$DATA_DIR/$SERVER_ICON"
    fi
fi

if [ ! -f "$DATA_DIR/pumpkin.toml" ] && [ -f "/defaults/pumpkin.toml" ]; then
    echo "[Config] Deploying base pumpkin.toml from defaults..."
    cp "/defaults/pumpkin.toml" "$DATA_DIR/pumpkin.toml"
fi

if [ ! -f "$DATA_DIR/data/ops.json" ] && [ -f "/defaults/data/ops.json" ]; then
    echo "[Config] Deploying base ops.json from defaults..."
    cp "/defaults/data/ops.json" "$DATA_DIR/data/ops.json"
fi

# --------------------------------------------------
# 2. Check & Fetch Pumpkin binary for Minecraft VERSION
# --------------------------------------------------
fetch_latest_release() {
    # If AUTO_UPDATE is false and binary already exists, skip network check entirely
    if [ "$AUTO_UPDATE" = "false" ] && [ -x "$BIN_PATH" ]; then
        echo "[Updater] AUTO_UPDATE is disabled and Pumpkin binary is installed. Skipping update check."
        ln -sf "$BIN_PATH" /usr/local/bin/pumpkin 2>/dev/null || true
        return 0
    fi

    echo "[Updater] Checking GitHub for Pumpkin release matching Minecraft ${VERSION}..."
    local releases_json
    releases_json=$(curl -sSL --connect-timeout 5 --max-time 15 "https://api.github.com/repos/Pumpkin-MC/Pumpkin/releases" 2>/dev/null || true)

    if [ -z "$releases_json" ] || echo "$releases_json" | grep -q "API rate limit exceeded"; then
        if [ -x "$BIN_PATH" ]; then
            echo "[Updater] Notice: GitHub API rate limited or unreachable. Using installed Pumpkin binary."
            ln -sf "$BIN_PATH" /usr/local/bin/pumpkin 2>/dev/null || true
            return 0
        else
            echo "[Updater] Error: Unable to reach GitHub releases and no local binary found!"
            exit 1
        fi
    fi

    local matched_release
    matched_release=$(echo "$releases_json" | jq -c --arg ver "$VERSION" '
        [ .[] | select((.tag_name | test("\\+" + $ver + "($|-)")) or (.name | test($ver))) ] | first
    ' 2>/dev/null || true)

    if [ -z "$matched_release" ] || [ "$matched_release" = "null" ]; then
        echo "[Updater] Warning: No specific tag found matching '+${VERSION}'. Falling back to latest release."
        matched_release=$(echo "$releases_json" | jq -c 'first' 2>/dev/null || true)
    fi

    local tag_name
    tag_name=$(echo "$matched_release" | jq -r '.tag_name // empty' 2>/dev/null || true)

    if [ -z "$tag_name" ]; then
        if [ -x "$BIN_PATH" ]; then
            echo "[Updater] Could not parse release tag. Using installed Pumpkin binary."
            ln -sf "$BIN_PATH" /usr/local/bin/pumpkin 2>/dev/null || true
            return 0
        fi
    fi

    echo "[Updater] Latest available release tag for MC ${VERSION}: ${tag_name}"

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
            if [ -x "$BIN_PATH" ]; then
                echo "[Updater] Warning: pumpkin-X64-Linux asset missing. Keeping installed binary."
                ln -sf "$BIN_PATH" /usr/local/bin/pumpkin 2>/dev/null || true
                return 0
            fi
            echo "[Updater] Error: pumpkin-X64-Linux asset not found in release ${tag_name}!"
            exit 1
        fi

        curl -sSL -o "$BIN_PATH" "$download_url"
        chmod +x "$BIN_PATH"
        ln -sf "$BIN_PATH" /usr/local/bin/pumpkin 2>/dev/null || true
        echo "$tag_name" > "$VERSION_FILE"
        echo "[Updater] Successfully installed Pumpkin (${tag_name}) to ${BIN_PATH}."
    else
        echo "[Updater] Pumpkin binary is up to date (${tag_name}). No download needed."
        ln -sf "$BIN_PATH" /usr/local/bin/pumpkin 2>/dev/null || true
    fi
}

fetch_latest_release

if [ ! -x "$BIN_PATH" ]; then
    echo "[Error] No executable Pumpkin binary found at ${BIN_PATH}!"
    exit 1
fi

# --------------------------------------------------
# 3. Synchronize environment variables into pumpkin.toml (Typed!)
# --------------------------------------------------
echo "[Config] Synchronizing server settings into pumpkin.toml..."
python3 - <<EOF
import re, os

config_path = "$DATA_DIR/pumpkin.toml"
try:
    with open(config_path, "r", encoding="utf-8") as f:
        content = f.read()
except Exception as e:
    print(f"Could not read {config_path}: {e}")
    content = ""

def set_val(section, key, val, val_type):
    global content
    if val_type == 'int':
        formatted = str(int(val))
    elif val_type == 'bool':
        formatted = 'true' if str(val).lower() in ('true', '1', 'yes') else 'false'
    elif val_type == 'str':
        formatted = f'"{val}"'
    else:
        formatted = str(val)

    if section == '':
        pattern = rf'^{re.escape(key)}\s*=.*$'
        if re.search(pattern, content, flags=re.MULTILINE):
            content = re.sub(pattern, f'{key} = {formatted}', content, flags=re.MULTILINE)
        else:
            content = f'{key} = {formatted}\n' + content
    else:
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
    set_val("", "seed", seed_val, "str")

set_val("", "default_gamemode", "$GAMEMODE", "str")
set_val("", "default_difficulty", "$DIFFICULTY", "str")
set_val("", "op_permission_level", "$DEFAULT_OP_LEVEL", "int")

# Server Icon (Favicon)
icon_file = "$SERVER_ICON"
if icon_file:
    set_val("", "use_favicon", "true", "bool")
    set_val("", "favicon_path", icon_file, "str")
else:
    set_val("", "use_favicon", "false", "bool")

# LAN broadcast
set_val("networking.lan_broadcast", "enabled", "$LAN_BROADCAST", "bool")

# Networking Java (Integers must be unquoted!)
set_val("networking.java", "max_players", "$MAX_PLAYERS", "int")
set_val("networking.java", "view_distance", "$VIEW_DISTANCE", "int")
set_val("networking.java", "simulation_distance", "$SIMULATION_DISTANCE", "int")
set_val("networking.java", "motd", "$MOTD", "str")
set_val("networking.java", "online_mode", "$ONLINE_MODE", "bool")

# Networking Bedrock (Integers must be unquoted!)
set_val("networking.bedrock", "max_players", "$MAX_PLAYERS", "int")
set_val("networking.bedrock", "view_distance", "$VIEW_DISTANCE", "int")
set_val("networking.bedrock", "simulation_distance", "$SIMULATION_DISTANCE", "int")
set_val("networking.bedrock", "motd", "$MOTD", "str")
set_val("networking.bedrock", "online_mode", "$ONLINE_MODE", "bool")

# Default OP level for non-ops in commands config (default 0)
non_op_level = os.environ.get("NON_OP_PERMISSION_LEVEL", "0")
set_val("commands", "default_op_level", non_op_level, "int")

with open(config_path, "w", encoding="utf-8") as f:
    f.write(content)

print(f"[Config] Settings written: max_players=$MAX_PLAYERS, view_distance=$VIEW_DISTANCE, icon=$SERVER_ICON, op_level=$DEFAULT_OP_LEVEL.")
EOF

# --------------------------------------------------
# 4. Synchronize Operator List (ops.json) with exact UUIDs
# --------------------------------------------------
OPS_FILE="$DATA_DIR/data/ops.json"
echo "[Config] Synchronizing operators in ${OPS_FILE}..."
python3 - <<EOF
import json, hashlib, uuid, os, urllib.request

ops_file = "${OPS_FILE}"
raw_ops_input = """${OP_ACCOUNTS}""".strip()
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

def get_pumpkin_sha256_uuid(name):
    """Pumpkin computes offline player UUID using SHA256(username)[:16]"""
    digest = hashlib.sha256(name.encode('utf-8')).digest()[:16]
    return str(uuid.UUID(bytes=digest))

def get_mojang_uuid(name):
    """Fetch official online Mojang UUID"""
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

# Support multiple operator accounts (comma, semicolon, or newline separated)
import re
usernames = [u.strip() for u in re.split(r'[,;\n\r]+', raw_ops_input) if u.strip()]
if usernames and "SOME_USER" not in [u.upper() for u in usernames]:
    existing_ops = [op for op in existing_ops if op.get("name") != "SOME_USER"]

for user in usernames:
    if not user or user.upper() == "SOME_USER":
        continue

    # In online mode, resolve official Mojang UUID; in offline mode, use Pumpkin's native SHA256 offline UUID
    resolved_uuid = None
    resolved_name = user
    uuid_type = "Pumpkin SHA256 offline"

    if online_mode:
        mojang_uuid, mojang_name = get_mojang_uuid(user)
        if mojang_uuid:
            resolved_uuid = mojang_uuid
            resolved_name = mojang_name
            uuid_type = "Mojang online"
        else:
            resolved_uuid = get_pumpkin_sha256_uuid(user)
    else:
        resolved_uuid = get_pumpkin_sha256_uuid(user)

    matched = False
    for op in existing_ops:
        if op.get("uuid") == resolved_uuid or op.get("name", "").lower() == resolved_name.lower():
            op["uuid"] = resolved_uuid
            op["name"] = resolved_name
            op["level"] = default_level
            op["bypassesPlayerLimit"] = op.get("bypassesPlayerLimit", False)
            matched = True
            print(f"[Config] Updated operator '{resolved_name}' ({uuid_type} UUID: {resolved_uuid}, Level: {default_level})")
            break

    if not matched:
        existing_ops.append({
            "uuid": resolved_uuid,
            "name": resolved_name,
            "level": default_level,
            "bypassesPlayerLimit": False
        })
        print(f"[Config] Added operator '{resolved_name}' ({uuid_type} UUID: {resolved_uuid}, Level: {default_level})")

with open(ops_file, "w", encoding="utf-8") as f:
    json.dump(existing_ops, f, indent=2)

print(f"[Config] Operator list successfully synchronized ({len(existing_ops)} entries).")
EOF

# --------------------------------------------------
# 5. Launch Pumpkin with signal handling & live logging
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
echo " Operators:         ${OP_ACCOUNTS:-none}"
echo " RAM Limit:         ${RAM_LIMIT:-unlimited (native Rust allocator)}"
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
