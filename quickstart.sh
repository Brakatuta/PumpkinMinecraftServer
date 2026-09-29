#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
REPO_DIR_NAME="$(basename "$SCRIPT_DIR")"

echo "=================================================="
echo "    Pumpkin Minecraft Server - Quickstart Setup   "
echo "=================================================="
echo "Repository: $SCRIPT_DIR"
echo "Deployment: $PARENT_DIR"
echo ""

COMPOSE_SRC="$SCRIPT_DIR/docker-compose.yml"
COMPOSE_DEST="$PARENT_DIR/docker-compose.yml"
ENV_SRC="$SCRIPT_DIR/.env.example"
ENV_DEST="$PARENT_DIR/.env"
DATA_DEST="$PARENT_DIR/server_data"

# 1. Deploy docker-compose.yml to parent directory
if [ -f "$COMPOSE_DEST" ]; then
    echo "[!] Notice: $COMPOSE_DEST already exists."
    # If forced via -y/--force or prompt user
    if [ "$1" = "-y" ] || [ "$1" = "--force" ]; then
        OVERWRITE="y"
    elif [ -t 0 ]; then
        read -r -p "    Overwrite parent docker-compose.yml? [y/N]: " OVERWRITE
    else
        OVERWRITE="n"
    fi

    if [[ "$OVERWRITE" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        sed "s|build: \.|build: ./${REPO_DIR_NAME}|g" "$COMPOSE_SRC" > "$COMPOSE_DEST"
        echo "[+] Updated $COMPOSE_DEST (build: ./${REPO_DIR_NAME})"
    else
        echo "[-] Kept existing $COMPOSE_DEST"
    fi
else
    sed "s|build: \.|build: ./${REPO_DIR_NAME}|g" "$COMPOSE_SRC" > "$COMPOSE_DEST"
    echo "[+] Created $COMPOSE_DEST (build: ./${REPO_DIR_NAME})"
fi

# 2. Deploy .env template to parent directory if missing
if [ ! -f "$ENV_DEST" ]; then
    cp "$ENV_SRC" "$ENV_DEST"
    echo "[+] Created $ENV_DEST with default configuration template."
else
    echo "[-] Existing .env found at $ENV_DEST (kept intact)."
fi

# 3. Create persistent storage directory in parent directory
mkdir -p "$DATA_DEST"
echo "[+] Ensured persistent data directory exists at $DATA_DEST"

echo ""
echo "=================================================="
echo " Setup Completed Successfully!                   "
echo "=================================================="
echo "Your server deployment is now decoupled from the git repo."
echo "You can pull updates anytime without git merge conflicts!"
echo ""
echo "To configure and launch your server:"
echo "  1. Switch to your project directory:"
echo "       cd .."
echo "  2. (Optional) Customize settings in .env:"
echo "       nano .env"
echo "  3. Launch server in background:"
echo "       docker compose up -d --build"
echo "       # or with podman:"
echo "       podman compose up -d --build"
echo ""
echo "To update Pumpkin in the future:"
echo "       cd $REPO_DIR_NAME && git pull && cd .. && docker compose up -d --build"
echo "=================================================="
