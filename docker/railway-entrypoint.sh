#!/bin/sh
# Railway entrypoint — bypasses s6-overlay, runs gateway directly.
set -e

HERMES_HOME="${HERMES_HOME:-/opt/data}"
INSTALL_DIR="/opt/hermes"

echo "[railway-entrypoint] Starting Hermes gateway..."

# Create data directory
mkdir -p "$HERMES_HOME"

# Seed directory structure
for sub in cron sessions logs hooks memories skills skins plans workspace home profiles; do
    mkdir -p "$HERMES_HOME/$sub"
done

# Seed config files (only on first boot)
seed_one() {
    dest=$1
    src=$2
    if [ ! -f "$HERMES_HOME/$dest" ] && [ -f "$INSTALL_DIR/$src" ]; then
        cp "$INSTALL_DIR/$src" "$HERMES_HOME/$dest"
        echo "[railway-entrypoint] Seeded $dest from $src"
    fi
}
seed_one ".env" ".env.example"
seed_one "config.yaml" "cli-config.yaml.example"

# Set permissions
chmod 600 "$HERMES_HOME/.env" 2>/dev/null || true
chmod 640 "$HERMES_HOME/config.yaml" 2>/dev/null || true

# Activate venv
. /opt/hermes/.venv/bin/activate

echo "[railway-entrypoint] Launching hermes gateway run..."
# Run the gateway
exec hermes gateway run
