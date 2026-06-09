#!/bin/bash
# install.sh — installs turtleneck_buffer.py into Klipper extras

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$SCRIPT_DIR/turtleneck_buffer.py"

# Common Klipper install locations, in priority order
KLIPPER_CANDIDATES=(
    "$HOME/klipper"
    "/home/pi/klipper"
    "/opt/klipper"
)

# ---- Locate Klipper ---------------------------------------------------------

KLIPPER_DIR=""
for candidate in "${KLIPPER_CANDIDATES[@]}"; do
    if [ -d "$candidate/klippy/extras" ]; then
        KLIPPER_DIR="$candidate"
        break
    fi
done

if [ -z "$KLIPPER_DIR" ]; then
    echo "ERROR: Could not find a Klipper installation."
    echo "       Looked in: ${KLIPPER_CANDIDATES[*]}"
    echo "       Re-run with KLIPPER_DIR=/path/to/klipper $0 to specify manually."
    exit 1
fi

EXTRAS_DIR="$KLIPPER_DIR/klippy/extras"

# ---- Install ----------------------------------------------------------------

echo "Klipper found at: $KLIPPER_DIR"

if [ ! -f "$SOURCE" ]; then
    echo "ERROR: turtleneck_buffer.py not found at $SOURCE"
    exit 1
fi

cp "$SOURCE" "$EXTRAS_DIR/turtleneck_buffer.py"
echo "Installed: $EXTRAS_DIR/turtleneck_buffer.py"

# ---- Restart Klipper (optional) ---------------------------------------------

if systemctl is-active --quiet klipper 2>/dev/null; then
    read -rp "Restart Klipper service now? [y/N] " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        sudo systemctl restart klipper
        echo "Klipper restarted."
    else
        echo "Skipped restart — remember to restart Klipper before the module takes effect."
    fi
else
    echo "Klipper service not detected — restart it manually when ready."
fi

echo "Done."
