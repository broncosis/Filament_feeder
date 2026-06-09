#!/bin/bash
# Filament Feeder Installer
# Choose between Belay (stable) or TurtleNeck Buffer (experimental)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- Colors ------------------------------------------------------------------

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

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

# ---- Helpers -----------------------------------------------------------------

# Copy a file to a directory, prompting before overwrite
copy_cfg() {
    local src="$1"
    local dst_dir="$2"
    local name
    name="$(basename "$src")"

    if [ -f "$dst_dir/$name" ]; then
        read -rp "  '$name' already exists — overwrite? [y/N] " yn
        if [[ ! "$yn" =~ ^[Yy]$ ]]; then
            echo "  Skipped: $name"
            return
        fi
    fi
    cp "$src" "$dst_dir/$name"
    echo -e "  ${GREEN}Installed:${NC} $dst_dir/$name"
}

# Extract a file from the turtleneck-buffer branch without switching branches.
# Tries local branch first, then origin/turtleneck-buffer.
get_from_turtleneck_branch() {
    local branch_path="$1"
    local dest="$2"

    if git -C "$SCRIPT_DIR" show "turtleneck-buffer:$branch_path" > "$dest" 2>/dev/null; then
        return 0
    elif git -C "$SCRIPT_DIR" show "origin/turtleneck-buffer:$branch_path" > "$dest" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# ---- Belay install -----------------------------------------------------------

install_belay() {
    echo ""
    echo -e "${CYAN}Installing Belay-based feeder setup...${NC}"
    echo ""
    echo "Copying config files to $CONFIG_DIR :"
    copy_cfg "$SCRIPT_DIR/feeder.cfg"       "$CONFIG_DIR"
    copy_cfg "$SCRIPT_DIR/exampleT0.cfg"    "$CONFIG_DIR"
    copy_cfg "$SCRIPT_DIR/clean_nozzle.cfg" "$CONFIG_DIR"

    echo ""
    echo -e "${GREEN}${BOLD}Done!${NC} Next steps:"
    echo ""
    echo "  1. Install Belay from Annex Engineering:"
    echo "       https://github.com/Annex-Engineering/Belay"
    echo ""
    echo "  2. Add to your printer.cfg:"
    echo "       [include feeder.cfg]"
    echo "       [include clean_nozzle.cfg]"
    echo "       # Copy exampleT0.cfg for each tool, rename, and [include] each one"
    echo ""
    echo "  3. Update feeder.cfg:"
    echo "       - MCU serial path (match your feeder board's USB ID)"
    echo "       - Sensor and button pins"
    echo "       - extruder_stepper extruder names (extruder, extruder1, ...)"
    echo "       - rotation_distance (re-calibrate if not using BMG)"
    echo "       - bucket_x / bucket_y (your purge bucket position)"
    echo "       - Bowden tube length (D parameter, default 1400)"
    echo ""
    echo "  4. Restart Klipper"
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
    TMP_PY="$(mktemp /tmp/turtleneck_buffer_XXXXXX.py)"

    echo ""
    echo "Installing turtleneck_buffer.py into Klipper extras:"

    # Prefer the local file (if already on turtleneck-buffer branch), then git
    if [ -f "$SCRIPT_DIR/turtleneck_buffer/turtleneck_buffer.py" ]; then
        cp "$SCRIPT_DIR/turtleneck_buffer/turtleneck_buffer.py" "$TMP_PY"
    elif get_from_turtleneck_branch "turtleneck_buffer/turtleneck_buffer.py" "$TMP_PY"; then
        echo "  (fetched from turtleneck-buffer git branch)"
    else
        echo -e "${RED}ERROR: Could not locate turtleneck_buffer.py${NC}"
        echo "  Ensure the turtleneck-buffer branch has been fetched:"
        echo "    git fetch origin turtleneck-buffer"
        rm -f "$TMP_PY"
        exit 1
    fi

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
    copy_cfg "$SCRIPT_DIR/feeder.cfg"       "$CONFIG_DIR"
    copy_cfg "$SCRIPT_DIR/clean_nozzle.cfg" "$CONFIG_DIR"

    # -- Offer example config --

    echo ""
    echo "Example TurtleNeck Buffer configs:"
    echo "  a) turtleneck_buffer_example.cfg — 5-tool printer"
    echo "  b) turtleneck_buffer_ricky.cfg   — 6-tool printer"
    echo "  s) Skip"
    read -rp "Copy an example config? [a/b/s]: " example_choice

    copy_example_cfg() {
        local filename="$1"
        local tmp
        tmp="$(mktemp /tmp/tb_example_XXXXXX.cfg)"

        if [ -f "$SCRIPT_DIR/turtleneck_buffer/$filename" ]; then
            cp "$SCRIPT_DIR/turtleneck_buffer/$filename" "$tmp"
        elif get_from_turtleneck_branch "turtleneck_buffer/$filename" "$tmp"; then
            : # got it
        else
            echo -e "  ${RED}Could not locate $filename${NC}"
            rm -f "$tmp"
            return
        fi

        if [ -f "$CONFIG_DIR/$filename" ]; then
            read -rp "  '$filename' already exists — overwrite? [y/N] " yn
            if [[ ! "$yn" =~ ^[Yy]$ ]]; then
                echo "  Skipped: $filename"
                rm -f "$tmp"
                return
            fi
        fi
        cp "$tmp" "$CONFIG_DIR/$filename"
        echo -e "  ${GREEN}Installed:${NC} $CONFIG_DIR/$filename"
        rm -f "$tmp"
    }

    case "$example_choice" in
        a|A) copy_example_cfg "turtleneck_buffer_example.cfg" ;;
        b|B) copy_example_cfg "turtleneck_buffer_ricky.cfg" ;;
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
