# turtleneck_buffer.py
# Klipper extra — TurtleNeck two-sensor buffer sync and jam detection.
#
# Drop-in replacement for Belay (secondary extruder sync) and BTT Smart
# Filament Sensor jam detection.  AFC config-param names used throughout
# so migrating to AFC requires only a section-header rename.
#
# Install: copy to klippy/extras/turtleneck_buffer.py
# Config:  [turtleneck_buffer <name>]  (one section per tool)


class TurtleneckBuffer:
    def __init__(self, config):
        self.printer   = config.get_printer()
        self.name      = config.get_name().split()[-1]

        # Required config
        self.advance_pin  = config.get('advance_pin')
        self.trailing_pin = config.get('trailing_pin')
        self.feeder_name  = config.get('extruder_stepper')

        # Optional config — names and defaults mirror AFC_buffer
        self.multiplier_high = config.getfloat('multiplier_high', 1.05, above=0.)
        self.multiplier_low  = config.getfloat('multiplier_low',  0.95, above=0.)
        self.sensitivity     = config.getint(
            'filament_error_sensitivity', 0, minval=0, maxval=10)

        # Runtime state
        self.state        = 'neutral'
        self.adv_state    = False   # True when advance pin active (buffer expanded)
        self.trl_state    = False   # True when trailing pin active (buffer compressed)
        self.feeder       = None    # ExtruderStepper — resolved in _handle_ready
        self.base_rd      = None    # base rotation_distance (float)
        self.steps_per_rot = None
        self.last_steps   = 0
        self.fault_dist   = ((11 - self.sensitivity) * 10.
                              if self.sensitivity > 0 else None)

        self.printer.register_event_handler('klippy:ready', self._handle_ready)

        # Per-instance mux GCode commands (dispatched by BUFFER=<name>)
        gcode = self.printer.lookup_object('gcode')
        gcode.register_mux_command(
            'QUERY_BUFFER', 'BUFFER', self.name, self.cmd_QUERY_BUFFER,
            desc="Report TurtleNeck buffer state and rotation_distance")
        gcode.register_mux_command(
            'SET_ROTATION_FACTOR', 'BUFFER', self.name,
            self.cmd_SET_ROTATION_FACTOR,
            desc="Apply a rotation factor directly to the feeder stepper")
        gcode.register_mux_command(
            'SET_BUFFER_MULTIPLIER', 'BUFFER', self.name,
            self.cmd_SET_BUFFER_MULTIPLIER,
            desc="Live-adjust multiplier_high or multiplier_low for this buffer")

        # Default jam handler — first instance wins; user may override with
        # [gcode_macro TURTLENECK_JAM] anywhere in their config.
        try:
            gcode.register_command(
                'TURTLENECK_JAM', self._cmd_default_jam,
                desc="Called on jam detection — override with [gcode_macro TURTLENECK_JAM]")
        except Exception:
            pass  # already registered by another instance or user gcode_macro

    # -------------------------------------------------------------------------
    # Startup
    # -------------------------------------------------------------------------

    def _handle_ready(self):
        self.feeder = self.printer.lookup_object(
            'extruder_stepper ' + self.feeder_name)
        self.base_rd, self.steps_per_rot = \
            self.feeder.stepper.get_rotation_distance()

        buttons = self.printer.lookup_object('buttons')
        buttons.register_buttons([self.advance_pin],  self._advance_handler)
        buttons.register_buttons([self.trailing_pin], self._trailing_handler)

        if self.fault_dist is not None:
            self.last_steps = self._feeder_steps()
            reactor = self.printer.get_reactor()
            reactor.register_timer(self._jam_check, reactor.monotonic() + 1.)

    # -------------------------------------------------------------------------
    # Sensor callbacks
    # -------------------------------------------------------------------------

    def _advance_handler(self, eventtime, state):
        # advance pin active → buffer is at expanded (advance) position
        self.adv_state = bool(state[0] if isinstance(state, list) else state)
        self._update(eventtime)

    def _trailing_handler(self, eventtime, state):
        # trailing pin active → buffer is at compressed (trailing) position
        self.trl_state = bool(state[0] if isinstance(state, list) else state)
        self._update(eventtime)

    def _update(self, eventtime):
        if self.feeder is None:
            return

        # Priority: trailing > advance > neutral
        if self.trl_state:
            # Buffer compressed — speed up feeder (lower rotation_distance)
            new_state, factor = 'advancing', self.multiplier_low
        elif self.adv_state:
            # Buffer expanded — slow feeder (raise rotation_distance)
            new_state, factor = 'trailing', self.multiplier_high
        else:
            new_state, factor = 'neutral', 1.

        if new_state != self.state:
            self.state = new_state
            self._set_rd(self.base_rd * factor)
            if self.fault_dist is not None:
                self.last_steps = self._feeder_steps()

    # -------------------------------------------------------------------------
    # Stepper helpers
    # -------------------------------------------------------------------------

    def _set_rd(self, rd):
        self.feeder.stepper.rotation_dist = rd

    def _feeder_steps(self):
        mcu_stepper = getattr(self.feeder.stepper, '_mcu_stepper', None)
        if mcu_stepper is None:
            return 0
        return mcu_stepper.get_commanded_position()

    # -------------------------------------------------------------------------
    # Jam detection
    # -------------------------------------------------------------------------

    def _jam_check(self, eventtime):
        if self.fault_dist is None or self.feeder is None:
            return self.printer.get_reactor().NEVER

        current_steps = self._feeder_steps()
        moved_mm = (abs(current_steps - self.last_steps)
                    * self.base_rd / self.steps_per_rot)

        if moved_mm >= self.fault_dist:
            # Identify which sensor is stuck
            sensor = ('advance'  if self.adv_state else
                      'trailing' if self.trl_state else 'unknown')
            self.last_steps = current_steps
            # Schedule gcode dispatch outside the timer callback
            self.printer.get_reactor().register_async_callback(
                lambda et, s=sensor: self._fire_jam(s))

        return eventtime + .5

    def _fire_jam(self, sensor):
        gcode = self.printer.lookup_object('gcode')
        gcode.run_script_from_command(
            "TURTLENECK_JAM TOOL=%s SENSOR=%s" % (self.name, sensor))

    # -------------------------------------------------------------------------
    # Default TURTLENECK_JAM handler (user-overridable)
    # -------------------------------------------------------------------------

    def _cmd_default_jam(self, gcmd):
        tool   = gcmd.get('TOOL', self.name)
        sensor = gcmd.get('SENSOR', 'unknown')
        gcmd.respond_info("Jam detected on %s (sensor: %s)" % (tool, sensor))
        self.printer.lookup_object('gcode').run_script_from_command('PAUSE')

    # -------------------------------------------------------------------------
    # GCode commands
    # -------------------------------------------------------------------------

    def cmd_QUERY_BUFFER(self, gcmd):
        rd = self.feeder.stepper.rotation_dist
        gcmd.respond_info(
            "Buffer %s  state=%s  rotation_distance=%.6f  base=%.6f"
            % (self.name, self.state, rd, self.base_rd))

    def cmd_SET_ROTATION_FACTOR(self, gcmd):
        factor = gcmd.get_float('FACTOR', above=0.)
        self._set_rd(self.base_rd * factor)
        gcmd.respond_info(
            "Buffer %s  rotation_distance=%.6f  factor=%.4f"
            % (self.name, self.feeder.stepper.rotation_dist, factor))

    def cmd_SET_BUFFER_MULTIPLIER(self, gcmd):
        which  = gcmd.get('MULTIPLIER').upper()
        factor = gcmd.get_float('FACTOR', above=0.)
        if which == 'HIGH':
            self.multiplier_high = factor
        elif which == 'LOW':
            self.multiplier_low = factor
        else:
            raise gcmd.error("MULTIPLIER must be HIGH or LOW, got: %s" % which)
        gcmd.respond_info(
            "Buffer %s  multiplier_%s=%.4f" % (self.name, which.lower(), factor))


def load_config_prefix(config):
    return TurtleneckBuffer(config)
