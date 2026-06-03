#!/bin/sh
# =============================================================================
# Railway entrypoint for hermes-agent
# Bypasses s6-overlay entirely. Handles data-dir setup, config seeding,
# venv activation, and launches `hermes gateway run`.
# =============================================================================
set -e

HERMES_HOME="${HERMES_HOME:-/opt/data}"
INSTALL_DIR="/opt/hermes"

# ─── Startup banner ──────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Hermes Agent — Railway Deployment                         ║"
echo "║  (s6-overlay bypass mode)                                   ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "[entrypoint] HERMES_HOME = $HERMES_HOME"
echo "[entrypoint] INSTALL_DIR = $INSTALL_DIR"
echo "[entrypoint] Timestamp   = $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo ""

# ─── Create data directory structure ─────────────────────────────────────────
echo "[entrypoint] Creating data directory structure..."
mkdir -p "$HERMES_HOME"
for sub in cron sessions logs hooks memories skills skins plans workspace home profiles; do
    mkdir -p "$HERMES_HOME/$sub"
done
echo "[entrypoint] Directory structure ready."

# ─── Seed config files from examples (first boot only) ──────────────────────
echo "[entrypoint] Seeding config files (skips if already present)..."

seed_one() {
    dest="$1"
    src="$2"
    if [ ! -f "$HERMES_HOME/$dest" ] && [ -f "$INSTALL_DIR/$src" ]; then
        cp "$INSTALL_DIR/$src" "$HERMES_HOME/$dest"
        echo "[entrypoint]   Seeded $dest from $src"
    elif [ -f "$HERMES_HOME/$dest" ]; then
        echo "[entrypoint]   $dest already exists — skipping."
    else
        echo "[entrypoint]   WARNING: $src not found in install dir — cannot seed $dest"
    fi
}

seed_one ".env" ".env.example"
seed_one "config.yaml" "cli-config.yaml.example"

# ─── Set permissions ────────────────────────────────────────────────────────
echo "[entrypoint] Setting config file permissions..."
chmod 600 "$HERMES_HOME/.env" 2>/dev/null || true
chmod 640 "$HERMES_HOME/config.yaml" 2>/dev/null || true
echo "[entrypoint]   .env       -> 600 (owner read/write only)"
echo "[entrypoint]   config.yaml -> 640 (owner rw, group r)"

# ─── Validate environment ───────────────────────────────────────────────────
echo ""
echo "[entrypoint] Validating environment..."
if [ ! -f "/opt/hermes/.venv/bin/activate" ]; then
    echo "[entrypoint] FATAL: Python venv not found at /opt/hermes/.venv/bin/activate"
    echo "[entrypoint] The Dockerfile may not have completed successfully."
    exit 1
fi
echo "[entrypoint]   Python venv: OK"
echo "[entrypoint]   Python:      $(python3 --version 2>&1 || echo 'not found')"
echo "[entrypoint]   Node:        $(node --version 2>&1 || echo 'not found')"
echo ""

# ─── Activate venv ──────────────────────────────────────────────────────────
echo "[entrypoint] Activating Python venv..."
. /opt/hermes/.venv/bin/activate
echo "[entrypoint]   Venv active. hermes binary: $(which hermes 2>/dev/null || echo 'not found')"
echo ""

# ─── Launch ──────────────────────────────────────────────────────────────────
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Launching: hermes gateway run                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

exec hermes gateway run
