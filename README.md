# Filament Feeder

> **Use this at your own risk.** This is how I did it — not the only way, and definitely not the officially supported way. That said, it works great on my setup and should be adaptable to most Klipper-based toolchangers with minor tweaks.

This project adds automated filament loading to a Klipper toolchanger. Filament sits outside the machine on a per-tool feeder extruder, and is pushed through a Bowden tube to the toolhead on demand. It was developed and tested on a Stealth Changer but the approach should work on any Klipper-based toolchanger.

Loading can be triggered automatically by a filament runout/insert sensor, or manually via macro. There are macros for both sensor-based and fixed-distance (no sensor) loading.

---

## How It Works

Each tool gets its own dedicated feeder extruder mounted externally. When filament is inserted (or a load command is issued), the feeder pushes filament down the Bowden tube toward the toolhead. A [Belay tensioner](https://github.com/Annex-Engineering/Belay) on each feeder keeps things in sync with the toolhead extruder during printing.

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
- **1 Belay sensor** — for sync feedback during printing ([Annex Engineering Belay](https://github.com/Annex-Engineering/Belay))
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
- A **`CLEAN_NOZZLE` macro** — called after purging

---

## Files in This Repo

| File | Description |
|------|-------------|
| `feeder.cfg` | Main config — feeder MCU, Belay tensioners, feeder steppers, unload buttons, and all macros |
| `T0.cfg` | Sample tool config — EBB CAN toolhead board, extruder, hotend fan, part fan, ADXL345, toolchanger tool definition, and all three filament sensors |
| `bmg_sfs2mount.stl` | BMG feeder mount with SFS2 sensor bracket |
| `bmg_sfs2mount_with button.stl` | Same but with tactile unload button |
| `sherpamount.stl` | Sherpa Mini feeder mount (test variant) |
| `BMG_Extruder.STEP` | STEP source for the BMG mount |
| `side panel spacer.stl` | Spacer for side panel mounting |

---

## Configuration

Copy `feeder.cfg` into your Klipper config directory and add `[include feeder.cfg]` to your `printer.cfg`.

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

Each tool uses up to three sensors, all defined in the tool's config file (e.g. `T0.cfg`). See the included `T0.cfg` for a complete working example.

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

## Questions / Discussion

I've documented this build on the Stealth Changer Discord: https://discordapp.com/channels/1226846451028725821/1401147182639481004

That's probably the best place to ask questions, compare notes, or share variations.
