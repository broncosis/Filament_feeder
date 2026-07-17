# Credits

## Annex Engineering — Belay
- **Author:** Annex Engineering
- **URL:** https://github.com/Annex-Engineering/Belay
- **License:** GPL v3
- **Used for:** Single-sensor buffer sync. The stable install path clones and runs the Belay installer.

## Armoured Turtle — TurtleNeck Buffer
- **Author:** Armoured Turtle
- **URL:** https://github.com/ArmouredTurtle
- **License:** GPL v3 (assumed — see repo for confirmation)
- **Used for:** Two-sensor buffer concept and hardware that `turtleneck_buffer.py` is designed to work with. The two-sensor approach and config parameter naming are derived from their work.

## CapTightpants — SIFM (Spoolman Interactive Filament Manager)
- **Author:** CapTightpants
- **URL:** https://github.com/CapTightpants/SIFM
- **License:** Unknown — used with explicit permission from the author
- **Used for:** The tip-forming wiggle sequence in `UNLOAD_ANY_TOOL` is based on `_SIFM_LOAD_FINISH` from SIFM. The Spoolman integration design (two-step spool selection prompt, transition mode concept, inter-macro state storage pattern) is also inspired by SIFM.

## Nic335 — Tool Router
- **Author:** Nic335
- **URL:** https://github.com/nic335
- **License:** Unknown — used with explicit permission from the author
- **Used for:** Tool router logic and macros provided by Nic335. `toolmap.cfg` (`_TOOLMAP`, `_TOOL_ROUTER`, `SET_TOOLMAP`, `SET_TOOL_FILAMENT_STATUS`, `RESET_TOOLMAP`, `SHOW_TOOLMAP`) — tool remapping and spool failover.
