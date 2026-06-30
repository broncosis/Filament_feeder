# Filament Feeder

> **Use this at your own risk.** This is how I did it — not the only way, and definitely not the officially supported way. That said, it works great on my setup and should be adaptable to most Klipper-based toolchangers with minor tweaks.

This project adds automated filament loading to a Klipper toolchanger. Filament sits outside the machine on a per-tool feeder extruder, and is pushed through a Bowden tube to the toolhead on demand. It was developed and tested on a Stealth Changer but the approach should work on any Klipper-based toolchanger.

Loading can be triggered automatically by a filament runout/insert sensor, or manually via macro. There are macros for both sensor-based and fixed-distance (no sensor) loading.

---

## Installation

Run this one-liner on your printer's SSH session — no cloning required:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/broncosis/Filament_feeder/main/install.sh)
```

The installer will detect your Klipper and config directories, then ask which sync module you want.

Two options are available:

### Option 1 — Belay (stable)

Uses [Annex Engineering's Belay](https://github.com/Annex-Engineering/Belay) for single-sensor buffer sync. This is the stable, well-tested path. The installer clones and runs the Belay installer automatically, then copies `feeder.cfg`, `exampleT0.cfg`, and `clean_nozzle.cfg` into your Klipper config directory.

### Option 2 — TurtleNeck Buffer (experimental)

> **⚠️ Still in testing.** This option works on my printer but may have bugs, and the configuration format could change. Try it if you're comfortable debugging Klipper extras.

A custom Klipper extra that replaces Belay with a two-sensor buffer sync and built-in jam detection. The installer drops `turtleneck_buffer.py` into your Klipper extras directory and copies the config files. No separate repo to clone — it's self-contained.

See the [TurtleNeck Buffer section](#turtleneck-buffer) below for full configuration details.

---

## How It Works

Each tool gets its own dedicated feeder extruder mounted externally. When filament is inserted (or a load command is issued), the feeder pushes filament down the Bowden tube toward the toolhead. A buffer/sync module on each feeder keeps things in sync with the toolhead extruder during printing.

Loading flow:
1. Tool is selected and toolhead moves to the purge bucket
2. Feeder does a fast blind pre-feed for most of the Bowden length
3. Sensor-checking loop kicks in for the final stretch (or fixed distance if no toolhead sensor)
4. Once filament is detected at the toolhead (or distance is reached), nozzle heats, purges, and cleans

---

## Hardware Requirements

Per tool you'll need:
- **1 feeder extruder** — I used BMG clones; they push faster than Sherpa Minis down long Bowden runs, but Sherpas work too (mount included). Any extruder with a fitting to secure the PTFE will work.
- **1 stepper driver** — I used a spare 8-bit board with 5 stepper drivers
- **1 Belay sensor** (Option 1) *or* **2 switch inputs for TurtleNeck Buffer** (Option 2) — for sync feedback during printing
- **2 input pins for the BTT Smart Sensor** (optional — a simple filament switch or even a button works fine)
- **1 optional unload button** — I used a 6mm tactile button per tool, wired to the feeder board

So roughly 3–5 input pins + 1 stepper driver per tool.

For the feeder extruder itself, I've included:
- A BMG mount with integrated filament switch and SFS2 sensor bracket (`bmg_sfs2mount.stl`, `bmg_sfs2mount_with button.stl`)
- A Sherpa Mini test mount (`sherpamount.stl`) — works but BMG pushes faster
- STEP file for the BMG mount if you want to modify it (`BMG_Extruder.STEP`)

For the Sherpa Mini variant with ECAS fitting and integrated filament sensor, see [this Printables model](https://www.printables.com/model/999921-sherpa-mini-with-ecas-and-integrated-filament-sens).

---

## Prerequisites

Your printer needs to have working:
- Homing and Quad Gantry Level (QGL) — the macros check for these before doing anything
- A **purge bucket and brush** — loading and unloading both move to the bucket
- A **`CLEAN_NOZZLE` macro** — called after purging to wipe the nozzle

A sample `CLEAN_NOZZLE` macro is included in `clean_nozzle.cfg`. The key variables to tune for your setup are:

| Variable | Description | Default |
|----------|-------------|---------|
| `start_x` | X position of the left edge of the brush | `30` |
| `start_y` | Y position of the brush | `-1` |
| `start_z` | Z height to wipe at | `0.7` |
| `wipe_dist` | Length of the brush in mm | `32` |
| `wipe_times` | Number of wipe passes | `8` |
| `wipe_speed` | Wipe speed in mm/s | `200` |
| `min_temp` | Minimum temp before wiping (heats to this if lower) | `150` |

The macro uses whatever temperature the nozzle was already targeting — it only heats to `min_temp` if the nozzle is cold, then restores the original target when done.

```ini
[gcode_macro CLEAN_NOZZLE]
variable_start_x: 30          # X position of the left edge of the brush
variable_start_y: -1          # Y position of the brush
variable_start_z: 0.7         # Z height to wipe at
variable_wipe_dist: 32        # Length of the brush in mm
variable_wipe_times: 8        # Number of wipe passes
variable_wipe_speed: 200      # Wipe speed in mm/s
variable_raise_distance: 25   # Z raise after wiping
variable_min_temp: 150        # Minimum temp to wipe at (heats up if below this)
gcode:
    {% if "xyz" not in printer.toolhead.homed_axes %}
        G28
    {% endif %}
    RESPOND TYPE=echo MSG="Cleaning nozzle"
    {% set heater = printer.toolhead.extruder %}
    {% set target_temp = printer[heater].target %}
    {% if target_temp < min_temp %}
        M104 S{min_temp}
    {% endif %}
    G90
    G1 X{start_x + (wipe_dist/2)} Y{start_y} F12000
    TEMPERATURE_WAIT SENSOR={heater} MINIMUM={min_temp}
    G1 Z{start_z} F1500
    G1 X{start_x} F{wipe_speed * 60}
    {% for wipes in range(1, (wipe_times + 1)) %}
        G1 X{start_x + wipe_dist} F{wipe_speed * 60}
        G1 X{start_x} F{wipe_speed * 60}
    {% endfor %}
    G1 Y0 X60
    G1 Y4 X60
    G1 Z{raise_distance}
    M104 S{target_temp}
```

---

## Files in This Repo

| File | Description |
|------|-------------|
| `install.sh` | Installer — choose Belay (stable) or TurtleNeck Buffer (experimental) |
| `feeder.cfg` | Main config — feeder MCU, Belay tensioners, feeder steppers, unload buttons, and all macros |
| `exampleT0.cfg` | Sample tool config — EBB CAN toolhead board, extruder, hotend fan, part fan, ADXL345, toolchanger tool definition, and all three filament sensors |
| `clean_nozzle.cfg` | Nozzle wipe macro |
| `turtleneck_buffer/` | TurtleNeck Buffer Klipper extra, install script, and example configs *(experimental)* |
| `bmg_sfs2mount.stl` | BMG feeder mount with SFS2 sensor bracket |
| `bmg_sfs2mount_with button.stl` | Same but with tactile unload button |
| `sherpamount.stl` | Sherpa Mini feeder mount (test variant) |
| `BMG_Extruder.STEP` | STEP source for the BMG mount |
| `side panel spacer.stl` | Spacer for side panel mounting |

---

## Configuration

Run `bash install.sh` to copy config files, or copy them manually. Add `[include feeder.cfg]` to your `printer.cfg`.

You'll need to update:
- **MCU serial path** — match your feeder board's USB ID
- **Sensor and button pins** — match your feeder board's pinout
- **`extruder_stepper` extruder names** — match your tool definitions (e.g. `extruder`, `extruder1`, etc.)
- **`rotation_distance`** — tuned for BMG 50:17 gear ratio; re-calibrate if using a different extruder
- **Purge bucket coordinates** (`bucket_x`, `bucket_y`) — set these to your bucket position
- **Bowden tube length** (`D` parameter, default `1400`) — measure your actual tube length

### Belay tensioner setup

Add the relevant Belay settings to your `printer.cfg` as documented in the [Belay repo](https://github.com/Annex-Engineering/Belay). Each tool's Belay section in `feeder.cfg` references its corresponding `extruder_stepper`.

### Toolhead filament sensors

Each tool uses up to three sensors, all defined in the tool's config file (e.g. `T0.cfg`). See the included `exampleT0.cfg` for a complete working example.

**1. Feeder-side switch sensor** (`filament_sensor_T{N}`) — mounted at the feeder extruder on the feeder MCU. Detects insert/runout at the feeder end and triggers `LOAD_ANY_TOOL` on insert:

```ini
[filament_switch_sensor filament_sensor_T0]
switch_pin: ^feeder:PH0
pause_on_runout: FALSE
runout_gcode:
    M118 Runout sensor T0 reports: Runout
insert_gcode:
    M118 Runout sensor T0 reports: Filament Detected
    LOAD_ANY_TOOL T=0 S=30 D=1660
```

**2. Toolhead arrival sensor** (`filament_sensor_at_T{N}`) — mounted on the toolhead board. This is what `LOAD_ANY_TOOL` checks during the feed loop to know when filament has arrived. The name must follow the `filament_sensor_at_T{N}` pattern exactly:

```ini
[filament_switch_sensor filament_sensor_at_T0]
switch_pin: ^EBBT0:PB8
pause_on_runout: FALSE
runout_gcode:
    M118 Runout sensor at T0 reports: No filament detected
insert_gcode:
    M118 Runout sensor at T0 reports: Filament detected
```

**3. Motion encoder sensor** (optional) — detects filament jams during printing by monitoring actual filament movement:

```ini
[filament_motion_sensor encoder_sensor_T0]
switch_pin: ^feeder:PB3
detection_length: 10
extruder: extruder
pause_on_runout: False
runout_gcode:
    {% if printer.print_stats.state == "printing" and not printer.pause_resume.is_paused %}
        PAUSE
        M117 Filament encoder runout
    {% endif %}
```

---

## Macros

### `LOAD_ANY_TOOL` — sensor-based load *(recommended)*

Requires a toolhead filament sensor. Does a fast pre-feed, then steps in small increments checking the sensor until filament is detected, then heats and purges.

```
LOAD_ANY_TOOL T=0 S=30 D=1360
```

| Parameter | Description | Default |
|-----------|-------------|---------|
| `T` | Tool number | required |
| `S` | Feed speed (mm/s) | `30` |
| `D` | Max feed distance / Bowden length (mm) | `1400` |

### `LOAD_ANY_TOOL_DIST` — fixed-distance load *(no sensor needed)*

Feeds exactly `D` mm. Measure your Bowden tube carefully.

```
LOAD_ANY_TOOL_DIST T=0 S=30 D=1360
```

Same parameters as above.

### `UNLOAD_ANY_TOOL`

Shapes the tip, retracts from the nozzle, then pulls filament back through the Bowden.

```
UNLOAD_ANY_TOOL T=0 S=30 D=1400
```

Unload buttons on the feeder box also call this automatically.

---

## TurtleNeck Buffer

> **⚠️ Experimental — still in testing.** Works on my printer but may have bugs. Configuration format may change.

TurtleNeck Buffer is a custom Klipper extra (`turtleneck_buffer.py`) that replaces Belay with a two-sensor design and adds built-in jam detection. Install it via `install.sh` option 2.

### How it differs from Belay

| | Belay | TurtleNeck Buffer |
|---|---|---|
| Sensors per tool | 1 | 2 (advance + trailing) |
| Sync logic | single threshold | three-state: neutral / advancing / trailing |
| Jam detection | no (uses BTT SFS separately) | built-in |
| Installation | separate repo | single `.py` file, included here |

### Configuration

Add a `[turtleneck_buffer TN]` section for each tool:

```ini
[turtleneck_buffer T0]
advance_pin: feeder:PA0        # buffer expanded — speed up
trailing_pin: feeder:PA1       # buffer compressed — slow down
extruder_stepper: feeder_t0
multiplier_high: 1.05          # speed multiplier when advancing
multiplier_low: 0.95           # speed multiplier when trailing
sensitivity: 5                 # jam detection threshold (0–10, higher = more sensitive)
```

| Parameter | Description |
|-----------|-------------|
| `advance_pin` | Switch that triggers when the buffer is fully expanded (filament tension low) |
| `trailing_pin` | Switch that triggers when the buffer is compressed (filament tension high) |
| `extruder_stepper` | Name of the `[extruder_stepper]` to control |
| `multiplier_high` | Speed multiplier applied when advancing (buffer expanded) |
| `multiplier_low` | Speed multiplier applied when trailing (buffer compressed) |
| `sensitivity` | Jam detection sensitivity 0–10. `0` = disabled, `10` = triggers after ~10 mm without buffer movement |

### Available commands

| Command | Description |
|---------|-------------|
| `QUERY_BUFFER BUFFER=T0` | Report current state and rotation_distance |
| `SET_ROTATION_FACTOR BUFFER=T0 FACTOR=1.02` | Directly adjust speed |
| `SET_BUFFER_MULTIPLIER BUFFER=T0 MULTIPLIER=HIGH FACTOR=1.05` | Tune high/low multipliers live |

### Jam detection

When the extruder moves more than `fault_distance` mm without the buffer state changing, the module calls the `TURTLENECK_JAM` macro. You can override this macro to trigger a pause, alert, or custom recovery:

```ini
[gcode_macro TURTLENECK_JAM]
gcode:
    PAUSE
    M117 Filament jam detected on {params.TOOL}
```

If `TURTLENECK_JAM` is not defined, the module logs a warning and continues.

### feeder.cfg with TurtleNeck Buffer

The same `feeder.cfg` is used, but you should **remove or comment out the `[belay]` sections** — TurtleNeck Buffer takes over that role. Everything else (steppers, macros, sensors) stays the same.

---

## Companion Projects

These are separate projects built to improve the experience around this feeder system. Neither is required — the feeder works without them — but together they make toolchanger filament management significantly more polished.

### KlipperScreen Filament Lanes

[broncosis/KlipperScreen-filament-lanes](https://github.com/broncosis/KlipperScreen-filament-lanes)

A custom KlipperScreen panel that gives you a live view of all your filament lanes on the printer touchscreen. Each tool gets a column showing spool color, material, and name pulled from Spoolman, with per-lane filament sensor status and tap-to-select tool switching. Works on 4, 5, 6+ tool setups automatically.

**Requires:** KlipperScreen, Moonraker with Spoolman integration, and the `LOAD_ANY_TOOL_DIST` / `UNLOAD_ANY_TOOL` macros from this repo. Works without spoolman-lane-sync, but shows richer data with it.

Install via the one-liner in that repo — it symlinks the panel into KlipperScreen and adds the config block.

### Spoolman Lane Sync

[broncosis/spoolman-lane-sync](https://github.com/broncosis/spoolman-lane-sync)

A small background service that syncs filament data from Spoolman into Moonraker's database so OrcaSlicer sees which material is loaded in each tool slot. Polls Spoolman every 30 seconds and listens on Moonraker's WebSocket for real-time updates. Backs off automatically if Happy Hare or AFC is already managing that data.

**Requires:** Python 3.10+, Moonraker, Spoolman. Runs as a systemd service and integrates with Moonraker's update manager for OTA updates.

Install by cloning the repo, running `install.sh`, and configuring the `.env` file with your Moonraker/Spoolman addresses.

---

## Credits

**[Annex Engineering](https://github.com/Annex-Engineering)** — for [Belay](https://github.com/Annex-Engineering/Belay), the single-sensor buffer sync module that this project is built around. Great hardware and great software — go check out their stuff.

**[Armoured Turtle](https://github.com/ArmouredTurtle)** — for the TurtleNeck buffer concept and hardware that the `turtleneck_buffer` Klipper extra is designed to work with. The two-sensor approach and the AFC config parameter naming both come from their work.

**[CapTightpants / SIFM](https://github.com/CapTightpants/SIFM)** — the tip-forming wiggle in `UNLOAD_ANY_TOOL` is based on the `_SIFM_LOAD_FINISH` sequence from SIFM (Spoolman Interactive Filament Manager). Used with permission from the author.

---

## Questions / Discussion

I've documented this build on the Stealth Changer Discord: https://discordapp.com/channels/1226846451028725821/1401147182639481004

That's probably the best place to ask questions, compare notes, or share variations.
