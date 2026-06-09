# turtleneck_buffer.py — Design Specification

## Overview

A standalone Klipper extra that adapts the Belay single-sensor sync logic for the TurtleNeck two-sensor buffer design. Intended as a drop-in replacement for Belay + BTT Smart Filament Sensor jam detection, with a clean migration path to AFC if the user later adopts it.

---

## Goals

- Replace Belay (secondary extruder sync) per tool
- Replace BTT Smart Filament Sensor jam detection per tool
- No AFC dependency
- Clean, complete removal path if migrating to AFC
- AFC config parameter names used throughout for migration compatibility
- Support arbitrary number of named instances (N tools, no hardcoded limit)

---

## Non-Goals

- Runout detection (handled externally — toolhead sensor or rewinder switch)
- Any modification to load/unload macros
- Multi-file architecture — single `.py` file only
- Any external dependencies beyond standard Klipper internals

---

## Hardware Context

- Printer: Bobby (5 tools), Ricky (6 tools, future)
- Secondary extruders are `extruder_stepper` objects (e.g. `_tool0_feeder`), not named extruders
- All feeder steppers on a shared `feeder` MCU
- TurtleNeck has two sensors: `advance` (buffer expanded) and `trailing` (buffer compressed)

---

## File Structure

```
klippy/extras/turtleneck_buffer.py   # single file, drop into extras/
```

No installer, no other files required.

---

## Config Section

Section name: `[turtleneck_buffer <name>]`

Named instances allow arbitrary tool count:

```ini
[turtleneck_buffer T0]
advance_pin: ^PA1               # required — AFC name match
trailing_pin: ^PA2              # required — AFC name match
extruder_stepper: _tool0_feeder # required — not in AFC (AFC manages this itself)
multiplier_high: 1.05           # optional, default 1.05 — AFC name + default match
multiplier_low: 0.95            # optional, default 0.95 — AFC name + default match
filament_error_sensitivity: 5   # optional, default 0 (disabled) — AFC name match
                                # 0 = disabled, 1 = least sensitive, 10 = most sensitive
                                # formula: fault_distance = (11 - sensitivity) * 10 mm
```

---

## Sensor Logic / State Machine

Three states per instance:

| State      | Condition                        | Action                                      |
|------------|----------------------------------|---------------------------------------------|
| `advancing`| trailing pin triggered           | apply `multiplier_low` to rotation_distance  |
| `trailing` | advance pin triggered            | apply `multiplier_high` to rotation_distance |
| `neutral`  | neither pin triggered            | no rotation_distance change                 |

- `multiplier_high` increases rotation_distance → slows secondary extruder → buffer compresses
- `multiplier_low` decreases rotation_distance → speeds secondary extruder → buffer expands
- Neutral zone provides hysteresis — no hunting

State mirrors AFC `AFC_buffer` logic exactly so behaviour is consistent pre/post migration.

---

## Jam Detection

Uses `filament_error_sensitivity` to derive a `fault_distance` in mm:

```
fault_distance = (11 - sensitivity) * 10
```

- Monitors extruder position
- If extruder travels `fault_distance` mm without a buffer state change, jam is triggered
- Sensitivity 0 disables fault detection entirely
- On trigger: calls `TURTLENECK_JAM` macro with `TOOL=<name>` and `SENSOR=<advance|trailing>`
  - `advance` stuck triggered → buffer expanding but not compressing → downstream clog
  - `trailing` stuck triggered → buffer compressing but not expanding → upstream feed problem

---

## Jam Macro

A default macro ships with the module as a GCode macro in the `.py` file:

```ini
[gcode_macro TURTLENECK_JAM]
description: Called when a jam is detected by turtleneck_buffer. Override to customise behaviour.
gcode:
    {action_respond_info("Jam detected on %s (sensor: %s)" % (params.TOOL, params.SENSOR))}
    PAUSE
```

User can override by redefining `[gcode_macro TURTLENECK_JAM]` in their own config. The module always calls the macro by name, so the override takes effect transparently.

---

## GCode Commands

Mirror AFC buffer commands exactly:

| Command | Parameters | Description |
|---|---|---|
| `QUERY_BUFFER` | `BUFFER=<name>` | Reports current state and rotation_distance of named instance |
| `SET_ROTATION_FACTOR` | `BUFFER=<name> FACTOR=<float>` | Directly applies a rotation factor to the extruder_stepper |
| `SET_BUFFER_MULTIPLIER` | `BUFFER=<name> MULTIPLIER=<HIGH\|LOW> FACTOR=<float>` | Live-adjusts multiplier_high or multiplier_low |

---

## Removal / AFC Migration Instructions

**To remove the module:**
1. Delete `turtleneck_buffer.py` from `klippy/extras/`
2. Remove all `[turtleneck_buffer <name>]` sections from config
3. Remove `[gcode_macro TURTLENECK_JAM]` if defined
4. Restart Klipper

Nothing else is modified by this module — no side effects to clean up.

**To migrate to AFC:**
1. Install AFC per its documentation
2. For each `[turtleneck_buffer <name>]` section:
   - Change section header to `[AFC_buffer <name>]`
   - Remove the `extruder_stepper` line (AFC manages stepper assignment itself)
   - All other parameters (`advance_pin`, `trailing_pin`, `multiplier_high`, `multiplier_low`, `filament_error_sensitivity`) copy across unchanged
3. Remove `turtleneck_buffer.py` and `[gcode_macro TURTLENECK_JAM]`
4. Follow AFC documentation for buffer assignment to lanes/steppers

---

## Example Full Config (Bobby, 5 tools)

```ini
[turtleneck_buffer T0]
advance_pin: ^feeder:PA1
trailing_pin: ^feeder:PA2
extruder_stepper: _tool0_feeder
multiplier_high: 1.05
multiplier_low: 0.95
filament_error_sensitivity: 5

[turtleneck_buffer T1]
advance_pin: ^feeder:PA3
trailing_pin: ^feeder:PA4
extruder_stepper: _tool1_feeder
multiplier_high: 1.05
multiplier_low: 0.95
filament_error_sensitivity: 5

[turtleneck_buffer T2]
advance_pin: ^feeder:PB1
trailing_pin: ^feeder:PB2
extruder_stepper: _tool2_feeder
multiplier_high: 1.05
multiplier_low: 0.95
filament_error_sensitivity: 5

[turtleneck_buffer T3]
advance_pin: ^feeder:PB3
trailing_pin: ^feeder:PB4
extruder_stepper: _tool3_feeder
multiplier_high: 1.05
multiplier_low: 0.95
filament_error_sensitivity: 5

[turtleneck_buffer T4]
advance_pin: ^feeder:PC1
trailing_pin: ^feeder:PC2
extruder_stepper: _tool4_feeder
multiplier_high: 1.05
multiplier_low: 0.95
filament_error_sensitivity: 5

[gcode_macro TURTLENECK_JAM]
description: Override this macro to customise jam response per printer
gcode:
    {action_respond_info("Jam detected on %s (sensor: %s)" % (params.TOOL, params.SENSOR))}
    PAUSE
```

---

## Key Implementation Notes for Coding

- Use `printer.lookup_object('extruder_stepper <name>')` to get stepper reference
- Modify `rotation_distance` via the stepper's `stepper` attribute at runtime
- Register buttons via `printer.lookup_object('buttons')` using `register_button`
- Jam detection timer via `reactor.register_timer`
- Each instance is fully independent — separate class, separate state, separate timer
- `load_config_prefix` used to support named instances
- Default macro registered via `printer.load_config` pattern or included as a separate `[gcode_macro]` block in a bundled `.cfg` file — TBD based on cleanest Klipper pattern
