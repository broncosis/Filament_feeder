#!/bin/bash
# Filament Feeder Installer
# Choose between Belay (stable) or TurtleNeck Buffer (experimental)
# Can be run from a cloned copy of the repo, or piped directly via curl.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_URL="https://raw.githubusercontent.com/broncosis/Filament_feeder"

# ---- Colors ------------------------------------------------------------------

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ---- Detect if running from a cloned repo ------------------------------------
# When piped via curl, SCRIPT_DIR won't have the repo files, so we download
# everything instead of copying from local paths.

IN_REPO=false
if [ -f "$SCRIPT_DIR/feeder.cfg" ] && git -C "$SCRIPT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    IN_REPO=true
fi

# ---- Auto-detect Klipper installation ----------------------------------------

KLIPPER_CANDIDATES=(
    "$HOME/klipper"
    "/home/pi/klipper"
    "/opt/klipper"
)

KLIPPER_DIR=""
for candidate in "${KLIPPER_CANDIDATES[@]}"; do
    if [ -d "$candidate/klippy/extras" ]; then
        KLIPPER_DIR="$candidate"
        break
    fi
done

# ---- Auto-detect Klipper config directory ------------------------------------

CONFIG_CANDIDATES=(
    "$HOME/printer_data/config"
    "$HOME/klipper_config"
    "/home/pi/printer_data/config"
    "/home/pi/klipper_config"
)

CONFIG_DIR=""
for candidate in "${CONFIG_CANDIDATES[@]}"; do
    if [ -d "$candidate" ]; then
        CONFIG_DIR="$candidate"
        break
    fi
done

# ---- Banner ------------------------------------------------------------------

echo ""
echo -e "${CYAN}${BOLD}╔═══════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║       Filament Feeder Installer       ║${NC}"
echo -e "${CYAN}${BOLD}╚═══════════════════════════════════════╝${NC}"
echo ""

if [ -n "$KLIPPER_DIR" ]; then
    echo -e "  Klipper:     ${GREEN}$KLIPPER_DIR${NC}"
else
    echo -e "  Klipper:     ${YELLOW}not found (will prompt if needed)${NC}"
fi

if [ -n "$CONFIG_DIR" ]; then
    echo -e "  Config dir:  ${GREEN}$CONFIG_DIR${NC}"
else
    echo -e "  Config dir:  ${YELLOW}not found (will prompt)${NC}"
fi

echo ""

# ---- Choose sync module ------------------------------------------------------

echo -e "${BOLD}Choose your buffer/sync module:${NC}"
echo ""
echo -e "  ${BOLD}1) Belay${NC}  (stable)"
echo "     Single-sensor buffer sync using Annex Engineering's Belay module"
echo "     Requires separate Belay installation from the Annex repo"
echo ""
echo -e "  ${BOLD}2) TurtleNeck Buffer${NC}  ${YELLOW}[EXPERIMENTAL — in testing]${NC}"
echo "     Two-sensor buffer sync with built-in jam detection"
echo "     Custom Klipper extra — installs as a drop-in replacement for Belay"
echo ""
read -rp "Enter choice [1/2]: " CHOICE

case "$CHOICE" in
    1) INSTALL_MODE="belay" ;;
    2) INSTALL_MODE="turtleneck" ;;
    *) echo "Invalid choice. Exiting."; exit 1 ;;
esac

# ---- Prompt for config dir if not found --------------------------------------

if [ -z "$CONFIG_DIR" ]; then
    echo ""
    read -rp "Enter your Klipper config directory path: " CONFIG_DIR
    CONFIG_DIR="${CONFIG_DIR%/}"
    if [ ! -d "$CONFIG_DIR" ]; then
        echo -e "${RED}ERROR: Directory not found: $CONFIG_DIR${NC}"
        exit 1
    fi
fi

# ---- File helpers ------------------------------------------------------------

# Fetch a file from the main branch — local copy if available, else download.
# Writes to $dest (a temp path the caller provides).
get_main_file() {
    local rel_path="$1"
    local dest="$2"
    if $IN_REPO && [ -f "$SCRIPT_DIR/$rel_path" ]; then
        cp "$SCRIPT_DIR/$rel_path" "$dest"
    else
        curl -fsSL "$REPO_URL/main/$rel_path" -o "$dest"
    fi
}

# Fetch a file from the turtleneck-buffer branch — tries git first when in
# repo, falls back to curl.
get_turtleneck_file() {
    local rel_path="$1"
    local dest="$2"
    if $IN_REPO; then
        if git -C "$SCRIPT_DIR" show "turtleneck-buffer:$rel_path" > "$dest" 2>/dev/null; then
            return 0
        elif git -C "$SCRIPT_DIR" show "origin/turtleneck-buffer:$rel_path" > "$dest" 2>/dev/null; then
            return 0
        fi
    fi
    curl -fsSL "$REPO_URL/turtleneck-buffer/$rel_path" -o "$dest"
}

# Download a file (via get_fn) and copy it into dst_dir, prompting on overwrite.
# Usage: install_file <rel_path> <dst_dir> <get_fn>
install_file() {
    local rel_path="$1"
    local dst_dir="$2"
    local get_fn="$3"
    local name
    name="$(basename "$rel_path")"
    local tmp
    tmp="$(mktemp /tmp/ff_XXXXXX)"

    "$get_fn" "$rel_path" "$tmp"

    if [ -f "$dst_dir/$name" ]; then
        read -rp "  '$name' already exists — overwrite? [y/N] " yn
        if [[ ! "$yn" =~ ^[Yy]$ ]]; then
            echo "  Skipped: $name"
            rm -f "$tmp"
            return
        fi
    fi
    cp "$tmp" "$dst_dir/$name"
    echo -e "  ${GREEN}Installed:${NC} $dst_dir/$name"
    rm -f "$tmp"
}

# ---- Belay install -----------------------------------------------------------

install_belay() {
    echo ""
    echo -e "${CYAN}Installing Belay-based feeder setup...${NC}"

    # -- Install Belay Klipper extra --

    if [ -z "$KLIPPER_DIR" ]; then
        echo ""
        read -rp "Enter your Klipper directory path: " KLIPPER_DIR
        KLIPPER_DIR="${KLIPPER_DIR%/}"
        if [ ! -d "$KLIPPER_DIR/klippy/extras" ]; then
            echo -e "${RED}ERROR: klippy/extras not found under $KLIPPER_DIR${NC}"
            exit 1
        fi
    fi

    echo ""
    echo "Installing Belay from Annex Engineering:"
    BELAY_TMP="$(mktemp -d /tmp/belay_XXXXXX)"
    git clone --quiet --depth 1 https://github.com/Annex-Engineering/Belay "$BELAY_TMP"

    if [ -f "$BELAY_TMP/install.sh" ]; then
        echo "  Running Belay install script..."
        # Pass KLIPPER_DIR so Belay's installer finds the right location
        KLIPPER_DIR="$KLIPPER_DIR" bash "$BELAY_TMP/install.sh"
    else
        # Fallback: find and copy the Klipper extra .py file
        BELAY_PY="$(find "$BELAY_TMP" -maxdepth 2 -name "belay.py" | head -1)"
        if [ -n "$BELAY_PY" ]; then
            cp "$BELAY_PY" "$KLIPPER_DIR/klippy/extras/belay.py"
            echo -e "  ${GREEN}Installed:${NC} $KLIPPER_DIR/klippy/extras/belay.py"
        else
            echo -e "  ${YELLOW}Warning: could not find belay.py in the Belay repo.${NC}"
            echo "  Install manually from: https://github.com/Annex-Engineering/Belay"
        fi
    fi
    rm -rf "$BELAY_TMP"

    # -- Copy config files --

    echo ""
    echo "Copying config files to $CONFIG_DIR :"
    install_file "feeder.cfg"       "$CONFIG_DIR" get_main_file
    install_file "exampleT0.cfg"    "$CONFIG_DIR" get_main_file
    install_file "clean_nozzle.cfg" "$CONFIG_DIR" get_main_file

    # -- Offer Klipper restart --

    echo ""
    if systemctl is-active --quiet klipper 2>/dev/null; then
        read -rp "Restart Klipper now? [y/N] " answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            sudo systemctl restart klipper
            echo -e "${GREEN}Klipper restarted.${NC}"
        else
            echo "Skipped — remember to restart Klipper before Belay takes effect."
        fi
    else
        echo "Klipper service not detected — restart it manually when ready."
    fi

    echo ""
    echo -e "${GREEN}${BOLD}Done!${NC} Next steps:"
    echo ""
    echo "  1. Add to your printer.cfg:"
    echo "       [include feeder.cfg]"
    echo "       [include clean_nozzle.cfg]"
    echo "       # Copy exampleT0.cfg for each tool, rename, and [include] each one"
    echo ""
    echo "  2. Update feeder.cfg:"
    echo "       - MCU serial path (match your feeder board's USB ID)"
    echo "       - Sensor and button pins"
    echo "       - extruder_stepper extruder names (extruder, extruder1, ...)"
    echo "       - rotation_distance (re-calibrate if not using BMG)"
    echo "       - bucket_x / bucket_y (your purge bucket position)"
    echo "       - Bowden tube length (D parameter, default 1400)"
    echo ""
    echo "  3. Restart Klipper"
}

# ---- TurtleNeck Buffer install -----------------------------------------------

install_turtleneck() {
    echo ""
    echo -e "${YELLOW}${BOLD}⚠  TurtleNeck Buffer is experimental and still in testing.${NC}"
    echo "   It may have bugs and the configuration format could change."
    echo ""
    read -rp "Continue? [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

    echo ""
    echo -e "${CYAN}Installing TurtleNeck Buffer...${NC}"

    # -- Install Klipper extra --

    if [ -z "$KLIPPER_DIR" ]; then
        echo ""
        read -rp "Enter your Klipper directory path: " KLIPPER_DIR
        KLIPPER_DIR="${KLIPPER_DIR%/}"
        if [ ! -d "$KLIPPER_DIR/klippy/extras" ]; then
            echo -e "${RED}ERROR: klippy/extras not found under $KLIPPER_DIR${NC}"
            exit 1
        fi
    fi

    EXTRAS_DIR="$KLIPPER_DIR/klippy/extras"
    TMP_PY="$(mktemp /tmp/ff_XXXXXX.py)"

    echo ""
    echo "Installing turtleneck_buffer.py into Klipper extras:"
    get_turtleneck_file "turtleneck_buffer/turtleneck_buffer.py" "$TMP_PY"

    if [ -f "$EXTRAS_DIR/turtleneck_buffer.py" ]; then
        read -rp "  turtleneck_buffer.py already exists — overwrite? [y/N] " yn
        if [[ "$yn" =~ ^[Yy]$ ]]; then
            cp "$TMP_PY" "$EXTRAS_DIR/turtleneck_buffer.py"
            echo -e "  ${GREEN}Installed:${NC} $EXTRAS_DIR/turtleneck_buffer.py"
        else
            echo "  Skipped Klipper extra."
        fi
    else
        cp "$TMP_PY" "$EXTRAS_DIR/turtleneck_buffer.py"
        echo -e "  ${GREEN}Installed:${NC} $EXTRAS_DIR/turtleneck_buffer.py"
    fi
    rm -f "$TMP_PY"

    # -- Copy config files --

    echo ""
    echo "Copying config files to $CONFIG_DIR :"
    install_file "feeder.cfg"       "$CONFIG_DIR" get_main_file
    install_file "clean_nozzle.cfg" "$CONFIG_DIR" get_main_file

    # -- Offer example config --

    echo ""
    echo "Example TurtleNeck Buffer configs:"
    echo "  a) turtleneck_buffer_example.cfg — 5-tool printer"
    echo "  b) turtleneck_buffer_ricky.cfg   — 6-tool printer"
    echo "  s) Skip"
    read -rp "Copy an example config? [a/b/s]: " example_choice

    case "$example_choice" in
        a|A) install_file "turtleneck_buffer/turtleneck_buffer_example.cfg" "$CONFIG_DIR" get_turtleneck_file ;;
        b|B) install_file "turtleneck_buffer/turtleneck_buffer_ricky.cfg"   "$CONFIG_DIR" get_turtleneck_file ;;
        *)   echo "  Skipped." ;;
    esac

    # -- Offer Klipper restart --

    echo ""
    if systemctl is-active --quiet klipper 2>/dev/null; then
        read -rp "Restart Klipper now? [y/N] " answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            sudo systemctl restart klipper
            echo -e "${GREEN}Klipper restarted.${NC}"
        else
            echo "Skipped — remember to restart Klipper before the module takes effect."
        fi
    else
        echo "Klipper service not detected — restart it manually when ready."
    fi

    echo ""
    echo -e "${GREEN}${BOLD}Done!${NC} Next steps:"
    echo ""
    echo "  1. Add to your printer.cfg:"
    echo "       [include feeder.cfg]"
    echo "       [include clean_nozzle.cfg]"
    echo "       # Add [turtleneck_buffer T0], [turtleneck_buffer T1], etc."
    echo "       # See the example config for full reference"
    echo ""
    echo "  2. Update feeder.cfg:"
    echo "       - MCU serial path"
    echo "       - extruder_stepper extruder names (extruder, extruder1, ...)"
    echo "       - rotation_distance (re-calibrate if not using BMG)"
    echo "       - bucket_x / bucket_y (your purge bucket position)"
    echo "       - Bowden tube length (D parameter, default 1400)"
    echo "       - Remove or comment out the [belay] sections (replaced by turtleneck_buffer)"
    echo ""
    echo "  3. Configure each [turtleneck_buffer TN] section:"
    echo "       - advance_pin / trailing_pin (two switches per tool)"
    echo "       - extruder_stepper (name of the feeder stepper)"
    echo "       - multiplier_high / multiplier_low (speed adjustment factors)"
    echo "       - sensitivity (0–10, jam detection threshold)"
    echo ""
    echo "  4. Restart Klipper"
    echo ""
    echo -e "  ${YELLOW}Note: TurtleNeck Buffer is still experimental. Report issues at${NC}"
    echo -e "  ${YELLOW}the Stealth Changer Discord: https://discordapp.com/channels/1226846451028725821/1401147182639481004${NC}"
}

# ---- Run selected install ----------------------------------------------------

case "$INSTALL_MODE" in
    belay)      install_belay ;;
    turtleneck) install_turtleneck ;;
esac

echo ""
