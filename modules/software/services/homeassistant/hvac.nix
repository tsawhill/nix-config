{
  config,
  lib,
  pkgs,
  ...
}:

# Schedule-driven cooling for the three Daikin heads.
#
# The heads share one outdoor unit, so they compete for a fixed amount of
# capacity. Two ideas follow from that:
#
#   * Rooms get a threshold, not a setpoint. A room does nothing until it rises
#     above its threshold, so "82 in the bedroom" means "ignore it below 82"
#     rather than "hold it at 82", and a loose room never calls for heat.
#   * Priority decides who wins when capacity runs out. On a hot day every head
#     calls at once and they all fall short; shedding the low-priority rooms
#     frees capacity so the important one actually gets cold.
#
# IR is open loop. Nothing here can read the units back, so the controller
# checks temperature progress before a bounded retry and treats stale sensors
# as a reason to stop rather than to keep guessing.

let
  rooms = {
    office = "Office";
    bedroom = "Bedroom";
    living_room = "Living Room";
  };
  roomNames = [
    "office"
    "bedroom"
    "living_room"
  ];

  tuning = {
    # Degrees below the threshold before a room stops. Without this a room
    # chatters on and off around a single number.
    hysteresis = 2;
    # The head is told to aim below the threshold, never at it: its own sensor
    # reads ceiling air and runs warm, so a setpoint at the threshold would let
    # it satisfy itself early and quit while the room is still warm.
    #
    # The gap scales with how far off the room is, because an inverter treats
    # its own error as a throttle. Ten degrees over gets near-full output; two
    # degrees over gets a nudge, so the room glides in instead of overshooting
    # and the compressor spends its time modulating rather than cycling.
    setpointBase = 1;
    setpointGain = 1.0;
    # Bottom of the generated code table.
    setpointFloor = 64;
    # Compressor protection. An inverter would rather run long and gentle.
    minRunMinutes = 10;
    minOffMinutes = 10;
    # Weather is advisory; local control works when it is unavailable.
    outdoorEntity = "weather.forecast_home";
    progressDegrees = 0.3;
    boostMinutes = 10;
    stallMinutes = 20;
    # Scale escalation waits from 1x to 2x across a 0–35°F outdoor/room gap.
    deltaForDoubleWait = 35;
    # A sensor quieter than this is not worth acting on.
    staleMinutes = 15;
    # A capacity pause is bounded and limited to one victim per stalled cycle.
    shedMinutes = 30;
    overridePriority = 10;
    # Manual max run: extreme setpoint and top fan for a fixed window per press.
    maxMinutes = 20;
    maxPriority = 20;
    # Auto mode. The gap keeps heat and cool thresholds apart, and switches
    # need sustained demand plus a guard since the last one.
    autoGap = 5;
    autoPersistMinutes = 15;
    autoGuardMinutes = 90;
  };

  minutesOf =
    stamp:
    let
      parts = lib.splitString ":" stamp;
    in
    # toIntBase10, because toInt rejects "00" as octal-ambiguous.
    (lib.toIntBase10 (builtins.elemAt parts 0)) * 60 + (lib.toIntBase10 (builtins.elemAt parts 1));

  block = from: label: blockRooms: {
    inherit from label;
    fromMinutes = minutesOf from;
    rooms = blockRooms;
  };

  # heatBelow applies in heat and auto. Apart from the bedroom overnight these
  # are still placeholders to be revisited before winter.

  # Fan is a preference, not a throttle. The setpoint already scales output and
  # the unit's own auto varies the fan with information we do not have, so this
  # only departs from auto where noise matters more than speed.

  # Asleep: only the bedroom matters, the rest just must not bake.
  sleeping = {
    bedroom = {
      coolAbove = 73;
      heatBelow = 65;
      priority = 10;
      fan = "quiet";
      airflow = "comfort";
    };
    office = {
      coolAbove = 82;
      heatBelow = 60;
      priority = 1;
      fan = "auto";
      airflow = "comfort";
    };
    living_room = {
      coolAbove = 82;
      heatBelow = 60;
      priority = 1;
      fan = "auto";
      airflow = "comfort";
    };
  };

  # Working. Taylor is in the office every day, weekends included.
  working = {
    office = {
      coolAbove = 76;
      heatBelow = 68;
      priority = 10;
      fan = "auto";
      airflow = "comfort";
    };
    living_room = {
      coolAbove = 78;
      heatBelow = 66;
      priority = 5;
      fan = "auto";
      airflow = "comfort";
    };
    bedroom = {
      coolAbove = 80;
      heatBelow = 60;
      priority = 1;
      fan = "auto";
      airflow = "comfort";
    };
  };

  # The bedroom pulls down while the office is still occupied, so it is at
  # temperature on arrival rather than starting from 80. Nobody is in there
  # yet, so it pulls down on auto and only goes quiet once Asleep begins.
  preBed = {
    bedroom = {
      coolAbove = 73;
      heatBelow = 65;
      priority = 10;
      fan = "auto";
      airflow = "comfort";
    };
    office = {
      coolAbove = 76;
      heatBelow = 68;
      priority = 5;
      fan = "auto";
      airflow = "comfort";
    };
    living_room = {
      coolAbove = 80;
      heatBelow = 60;
      priority = 1;
      fan = "auto";
      airflow = "comfort";
    };
  };

  schedule = {
    days = {
      monday = "workday";
      tuesday = "workday";
      wednesday = "workday";
      thursday = "workday";
      friday = "fridayNight";
      saturday = "weekendLate";
      sunday = "weekend";
    };
    patterns = {
      workday = [
        (block "00:00" "Asleep" sleeping)
        (block "06:00" "Working" working)
        (block "22:00" "Wind-down" preBed)
      ];
      # No work the next morning, so bed is later.
      fridayNight = [
        (block "00:00" "Asleep" sleeping)
        (block "06:00" "Working" working)
        (block "23:30" "Wind-down" preBed)
      ];
      weekendLate = [
        (block "00:00" "Asleep" sleeping)
        (block "09:30" "Working" working)
        (block "23:30" "Wind-down" preBed)
      ];
      # Sunday night returns to the work-week bedtime.
      weekend = [
        (block "00:00" "Asleep" sleeping)
        (block "09:30" "Working" working)
        (block "22:00" "Wind-down" preBed)
      ];
    };
  };

  # Without the gap, auto would heat and cool the same room in turn.
  scheduleJson =
    assert lib.assertMsg (lib.all (
      b: lib.all (r: r.coolAbove - r.heatBelow >= tuning.autoGap) (lib.attrValues b.rooms)
    ) (lib.concatLists (lib.attrValues schedule.patterns))) "hvac: every block needs coolAbove - heatBelow >= ${toString tuning.autoGap}";
    builtins.toJSON schedule;

  tempSensor = room: "sensor.ac_controller_${room}_temperature";
  climateEntity = room: "climate.${room}_ac";
  overrideTimer = room: "timer.hvac_override_${room}";
  shedTimer = room: "timer.hvac_shed_${room}";
  # The cool side keeps the old entity id so overrides survive the upgrade.
  overrideNumber = room: "input_number.hvac_override_${room}";
  overrideHeatNumber = room: "input_number.hvac_override_heat_${room}";
  overrideLabel = room: "input_text.hvac_override_label_${room}";
  draftNumber = room: "input_number.hvac_draft_${room}";
  draftEnable = room: "input_boolean.hvac_draft_enable_${room}";
  draftFan = room: "input_select.hvac_draft_fan_${room}";
  draftAirflow = room: "input_select.hvac_draft_airflow_${room}";
  appliedFan = room: "input_select.hvac_override_fan_${room}";
  appliedAirflow = room: "input_select.hvac_override_airflow_${room}";
  draftMode = "input_select.hvac_draft_mode";
  commitIdle = {
    condition = "state";
    entity_id = "script.hvac_apply_override";
    state = "off";
  };
  startTempNumber = room: "input_number.hvac_start_temp_${room}";
  minRunTimer = room: "timer.hvac_min_run_${room}";
  minOffTimer = room: "timer.hvac_min_off_${room}";
  targetSensor = room: "sensor.hvac_target_${room}";
  heatTargetSensor = room: "sensor.hvac_heat_target_${room}";
  prioritySensor = room: "sensor.hvac_priority_${room}";
  maxTimer = room: "timer.hvac_max_${room}";
  maxMode = "input_select.hvac_max_mode";
  needSensor = room: "sensor.hvac_need_${room}";
  requestedMode = "sensor.hvac_requested_mode";
  autoSide = "input_select.hvac_auto_side";
  autoWantSince = "input_number.hvac_auto_want_since";
  autoSwitchedAt = "input_number.hvac_auto_switched_at";

  # One outdoor unit means the heads cannot run opposing modes, so this is a
  # single system-wide choice rather than a per-room one. systemMode is the
  # seasonal baseline; overrideMode is the temporary one, and it expires with
  # the override timers so an hour of heat cannot quietly become a whole
  # morning of it.
  systemMode = "input_select.hvac_system_mode";
  overrideMode = "input_select.hvac_override_mode";
  followSystem = "follow system";
  effectiveMode = "sensor.hvac_effective_mode";
  enableToggle = room: "input_boolean.hvac_enable_${room}";

  # Airflow comes from the schedule, same as fan, with a per-room pin. It has
  # to ride in SmartIR's swing dimension because the protocol sends full
  # state: anything sending its own IR would be wiped by the next setpoint
  # change. One select rather than two switches, since comfort holds the flap
  # at a fixed angle and swing sweeps it, so they were never combinable.
  airflowSelect = room: "input_select.hvac_airflow_${room}";
  airflowSensor = room: "sensor.hvac_airflow_${room}";
  airflowFollowsSchedule = "schedule";
  airflowOptions = [
    airflowFollowsSchedule
    "off"
    "swing"
    "comfort"
  ];

  # "schedule" defers to the block; anything else pins that speed until
  # changed back. Fan costs nothing in the code table, which already carries
  # every speed.
  fanSelect = room: "input_select.hvac_fan_${room}";
  fanSensor = room: "sensor.hvac_fan_${room}";
  fanFollowsSchedule = "schedule";
  fanOptions = [
    fanFollowsSchedule
    "auto"
    "quiet"
    "1"
    "2"
    "3"
    "4"
    "5"
  ];

  airflowTemplate = room: ''
    ${currentBlock}
    {%- if is_state('${overrideTimer room}', 'active') and states('${appliedAirflow room}') in ['off', 'swing', 'comfort'] -%}
      {{ states('${appliedAirflow room}') }}
    {%- elif is_state('${airflowSelect room}', '${airflowFollowsSchedule}') -%}
      {{ ns.current.rooms['${room}'].airflow }}
    {%- else -%}
      {{ states('${airflowSelect room}') }}
    {%- endif -%}'';

  anyOverrideActive = lib.concatStringsSep " or " (
    map (room: "is_state('${overrideTimer room}', 'active')") roomNames
  );

  anyMaxActive = lib.concatStringsSep " or " (
    map (room: "is_state('${maxTimer room}', 'active')") roomNames
  );

  # What the system and overrides ask for, which may be auto.
  requestedModeTemplate = ''
    {%- if (${anyOverrideActive}) and not is_state('${overrideMode}', '${followSystem}') -%}
      {{ states('${overrideMode}') }}
    {%- else -%}
      {{ states('${systemMode}') }}
    {%- endif -%}'';

  # The concrete mode before any max run; auto uses the side last picked.
  baseModeTemplate = ''
    {%- set requested -%}${requestedModeTemplate}{%- endset -%}
    {{- states('${autoSide}') if requested | trim == 'auto' else requested | trim -}}'';

  # A max run owns the shared outdoor unit for its window.
  effectiveModeTemplate = ''
    {%- if ${anyMaxActive} -%}
      {{ states('${maxMode}') }}
    {%- else -%}
      ${baseModeTemplate}
    {%- endif -%}'';

  # False while the sensor lags its inputs, e.g. the instant a max timer starts.
  settledTemplate = ''
    {%- set live -%}${effectiveModeTemplate}{%- endset -%}
    {{ live | trim == states('${effectiveMode}') }}'';

  # Rooms left out of a max run stay off so the chosen ones get the whole unit.
  preemptedTemplate = room: ''
    {%- set preempted = (${anyMaxActive}) and not is_state('${maxTimer room}', 'active') -%}'';

  # Resolve today's pattern and the block covering the current minute. Every
  # tag trims its own whitespace: Home Assistant types rendered results
  # natively, and a stray newline turns a number or a boolean into a string.
  currentBlock = ''
    {%- set schedule = ${scheduleJson} -%}
    {%- set blocks = schedule.patterns[schedule.days[now().strftime('%A') | lower]] -%}
    {%- set mins = now().hour * 60 + now().minute -%}
    {%- set ns = namespace(current = blocks[0]) -%}
    {%- for b in blocks -%}
      {%- if mins >= b.fromMinutes -%}{%- set ns.current = b -%}{%- endif -%}
    {%- endfor -%}'';

  # An active override replaces the scheduled value for as long as it runs.
  targetTemplate = room: ''
    ${currentBlock}
    {%- if is_state('${overrideTimer room}', 'active') -%}
      {{ states('${overrideNumber room}') | float(75) | round(0) }}
    {%- else -%}
      {{ ns.current.rooms['${room}'].coolAbove }}
    {%- endif -%}'';

  heatTargetTemplate = room: ''
    ${currentBlock}
    {%- if is_state('${overrideTimer room}', 'active') -%}
      {{ states('${overrideHeatNumber room}') | float(68) | round(0) }}
    {%- else -%}
      {{ ns.current.rooms['${room}'].heatBelow }}
    {%- endif -%}'';

  priorityTemplate = room: ''
    ${currentBlock}
    {%- if is_state('${maxTimer room}', 'active') -%}
      ${toString tuning.maxPriority}
    {%- elif is_state('${overrideTimer room}', 'active') -%}
      ${toString tuning.overridePriority}
    {%- else -%}
      {{ ns.current.rooms['${room}'].priority }}
    {%- endif -%}'';

  normalFanTemplate = room: ''
    ${currentBlock}
    {%- if is_state('${overrideTimer room}', 'active') and states('${appliedFan room}') in ['auto', 'quiet', '1', '2', '3', '4', '5'] -%}
      {{ states('${appliedFan room}') }}
    {%- elif is_state('${fanSelect room}', '${fanFollowsSchedule}') -%}
      {{ ns.current.rooms['${room}'].fan }}
    {%- else -%}
      {{ states('${fanSelect room}') }}
    {%- endif -%}'';

  fanTemplate = room: ''
    {%- set normal = states('sensor.hvac_normal_fan_${room}') -%}
    {{ '5' if is_state('${maxTimer room}', 'active') or (normal == 'auto' and states('input_select.hvac_watch_${room}') in ['boosted', 'stalled', 'exhausted', 'settled'] and states('${climateEntity room}') in ['cool', 'heat']) else normal }}'';

  # Which block of today's pattern is in force, for the dashboard.
  scheduleBlockTemplate = ''
    ${currentBlock}
    {{- ns.current.label }} since {{ ns.current.from -}}'';

  nextBlockTemplate = ''
    ${currentBlock}
    {%- set next = namespace(block = none) -%}
    {%- for b in blocks -%}
      {%- if b.fromMinutes > mins and next.block is none -%}{%- set next.block = b -%}{%- endif -%}
    {%- endfor -%}
    {%- if next.block is none -%}
      {%- set tomorrow = (now() + timedelta(days=1)).strftime('%A') | lower -%}
      {%- set next.block = schedule.patterns[schedule.days[tomorrow]][0] -%}
    {%- endif -%}
    {{ next.block.label }} at {{ next.block.from }}'';

  # Resolve what the room should be doing into one value, so the automation
  # below is "apply this" rather than a tree of cool and heat branches. Holding
  # the current mode inside the hysteresis band is what stops a room chattering
  # on and off around a single number. A max run is time-boxed, so it skips
  # thresholds, the room toggle, shedding and sensor health.
  desiredTemplate = room: ''
    ${preemptedTemplate room}
    {%- set sys = states('${effectiveMode}') -%}
    {%- set enabled = not is_state('${overrideTimer room}', 'active') or not is_state('${enableToggle room}', 'off') -%}
    {%- set r = states('${tempSensor room}') | float(-999) -%}
    {%- set ct = states('${targetSensor room}') | float(999) -%}
    {%- set ht = states('${heatTargetSensor room}') | float(-999) -%}
    {%- set cur = states('${climateEntity room}') -%}
    {%- set blocked = (not enabled) or preempted or sys == 'off' or is_state('${shedTimer room}', 'active')
        or states('${tempSensor room}') in ['unknown', 'unavailable']
        or (as_timestamp(now()) - as_timestamp(states.sensor.ac_controller_${room}_temperature.last_reported, 0)) > ${
          toString (tuning.staleMinutes * 60)
        } -%}
    {%- if is_state('${maxTimer room}', 'active') and sys in ['cool', 'heat'] -%}{{ sys }}
    {%- elif blocked -%}off
    {%- elif sys == 'cool' -%}
      {{ 'cool' if r > ct else ('off' if r <= ct - ${toString tuning.hysteresis} else (cur if cur == 'cool' else 'off')) }}
    {%- elif sys == 'heat' -%}
      {{ 'heat' if r < ht else ('off' if r >= ht + ${toString tuning.hysteresis} else (cur if cur == 'heat' else 'off')) }}
    {%- else -%}off
    {%- endif -%}'';

  # Which side the room would ask the shared unit for, whatever the mode.
  needTemplate = room: ''
    {%- set r = states('${tempSensor room}') -%}
    {%- if not is_number(r)
        or (as_timestamp(now()) - as_timestamp(states.sensor.ac_controller_${room}_temperature.last_reported, 0)) > ${
          toString (tuning.staleMinutes * 60)
        }
        or (is_state('${overrideTimer room}', 'active') and is_state('${enableToggle room}', 'off')) -%}none
    {%- elif r | float > states('${targetSensor room}') | float(999) -%}cool
    {%- elif r | float < states('${heatTargetSensor room}') | float(-999) -%}heat
    {%- else -%}none
    {%- endif -%}'';

  # True when the other side's most important need outranks everything still
  # needing or running on the current side. Ties stay put.
  autoSwitchTemplate = ''
    {%- set side = states('${autoSide}') -%}
    {%- set ns = namespace(cur = -1, other = -1) -%}
    {%- for room in ${builtins.toJSON roomNames} -%}
      {%- set need = states('sensor.hvac_need_' ~ room) -%}
      {%- set p = states('sensor.hvac_priority_' ~ room) | int(0) -%}
      {%- if need == side or is_state('climate.' ~ room ~ '_ac', side) -%}
        {%- set ns.cur = [ns.cur, p] | max -%}
      {%- elif need in ['cool', 'heat'] -%}
        {%- set ns.other = [ns.other, p] | max -%}
      {%- endif -%}
    {%- endfor -%}
    {{ ns.other > ns.cur }}'';

  # The gap below (cooling) or above (heating) the threshold scales with how
  # far off the room is, because the head treats its own error as a throttle.
  setpointTemplate = room: ''
    {%- set sys = states('${effectiveMode}') -%}
    {%- set r = states('${tempSensor room}') | float(0) -%}
    {%- if is_state('${maxTimer room}', 'active') -%}
      {{ 86 if sys == 'heat' else ${toString tuning.setpointFloor} }}
    {%- elif sys == 'heat' -%}
      {%- set ht = states('${heatTargetSensor room}') | float(68) -%}
      {{ [[ht + (${toString tuning.setpointBase} + ${toString tuning.setpointGain} * [ht - r, 0] | max), 86] | min, ${toString tuning.setpointFloor}] | max | round(0) }}
    {%- else -%}
      {%- set ct = states('${targetSensor room}') | float(75) -%}
      {{ [[ct - (${toString tuning.setpointBase} + ${toString tuning.setpointGain} * [r - ct, 0] | max), ${toString tuning.setpointFloor}] | max, 86] | min | round(0) }}
    {%- endif -%}'';

  # Single-line on purpose, for the same native-typing reason. as_timestamp
  # takes a default, which covers an entity that does not exist yet.
  roomVariables = room: {
    desired = desiredTemplate room;
    current_mode = "{{ states('${climateEntity room}') }}";
    min_run_active = "{{ is_state('${minRunTimer room}', 'active') }}";
    min_off_active = "{{ is_state('${minOffTimer room}', 'active') }}";
    maxed = "{{ is_state('${maxTimer room}', 'active') }}";
    setpoint = setpointTemplate room;
    airflow = "{{ states('${airflowSensor room}') }}";
    current_airflow = "{{ state_attr('${climateEntity room}', 'swing_mode') }}";
    fan = "{{ states('${fanSensor room}') }}";
    current_fan = "{{ state_attr('${climateEntity room}', 'fan_mode') }}";
    settled = settledTemplate;
  };

  offAction = room: {
    action = "climate.set_hvac_mode";
    target.entity_id = climateEntity room;
    data.hvac_mode = "off";
  };

  mkRoomAutomation = room: {
    alias = "HVAC ${rooms.${room}}";
    description = "Drive ${rooms.${room}} toward the threshold in force for the current mode.";
    mode = "single";
    triggers = [
      {
        trigger = "state";
        entity_id = tempSensor room;
      }
      {
        trigger = "state";
        entity_id = targetSensor room;
        id = "target";
      }
      {
        trigger = "state";
        entity_id = heatTargetSensor room;
        id = "target";
      }
      {
        trigger = "state";
        entity_id = shedTimer room;
      }
      {
        trigger = "state";
        entity_id = overrideTimer room;
      }
      {
        trigger = "state";
        entity_id = maxTimer room;
        id = "target";
      }
      {
        trigger = "state";
        entity_id = effectiveMode;
      }
      {
        trigger = "state";
        entity_id = "script.hvac_apply_override";
        to = "off";
        id = "target";
      }
      {
        trigger = "state";
        entity_id = "script.hvac_mode_handoff";
        to = "off";
      }
      {
        trigger = "state";
        entity_id = enableToggle room;
      }
      {
        trigger = "state";
        entity_id = airflowSensor room;
      }

      {
        trigger = "state";
        entity_id = fanSensor room;
      }
      {
        trigger = "time_pattern";
        minutes = "/1";
      }
    ];
    conditions = [
      commitIdle
      {
        condition = "state";
        entity_id = "script.hvac_mode_handoff";
        state = "off";
      }
    ];
    actions = [
      { variables = roomVariables room; }
      {
        choose = [
          # Stopping covers everything at once: disabled, system off, shed,
          # satisfied, or a sensor we cannot trust.
          {
            conditions = [
              {
                condition = "template";
                value_template = "{{ desired == 'off' and current_mode != 'off' and not min_run_active }}";
              }
            ];
            sequence = [ (offAction room) ];
          }
          # Start, switch mode, or correct a setpoint that has drifted. A max
          # press is a one-off, not chatter, so it skips the minimum off time.
          {
            conditions = [
              {
                condition = "template";
                value_template = ''
                  {{ desired != 'off' and settled
                     and (current_mode != desired
                          or (trigger.id | default("") == 'target' and (state_attr('${climateEntity room}', 'temperature') | float(0)) != setpoint))
                     and (current_mode != 'off' or not min_off_active or maxed)
                     and is_state('script.hvac_mode_handoff', 'off')
                     and (as_timestamp(now()) - as_timestamp(states.sensor.hvac_effective_mode.last_changed, 0)) >= 10 }}'';
              }
            ];
            sequence = [
              {
                action = "climate.set_temperature";
                target.entity_id = climateEntity room;
                data = {
                  hvac_mode = "{{ desired }}";
                  temperature = "{{ setpoint }}";
                };
              }
            ];
          }
          # Fan changed while running, whether from the schedule or a pin.
          {
            conditions = [
              {
                condition = "template";
                value_template = ''
                  {{ desired != 'off' and settled and current_mode == desired
                     and fan not in ['unknown', 'unavailable'] and fan != current_fan }}'';
              }
            ];
            sequence = [
              {
                action = "climate.set_fan_mode";
                target.entity_id = climateEntity room;
                data.fan_mode = "{{ fan }}";
              }
            ];
          }
          # Airflow changed while running. Only worth sending to a head that
          # is on: with it off SmartIR would just retransmit the off code.
          {
            conditions = [
              {
                condition = "template";
                value_template = ''
                  {{ desired != 'off' and settled and current_mode == desired
                     and airflow != current_airflow }}'';
              }
            ];
            sequence = [
              {
                action = "climate.set_swing_mode";
                target.entity_id = climateEntity room;
                data.swing_mode = "{{ airflow }}";
              }
            ];
          }

        ];
      }
    ];
  };

  modeHandoffAutomation = {
    alias = "HVAC mode handoff";
    mode = "restart";
    triggers = [
      {
        trigger = "homeassistant";
        event = "start";
      }
      {
        trigger = "state";
        entity_id = effectiveMode;
        to = null;
      }
    ];
    conditions = [
      {
        condition = "template";
        value_template = "{{ states('${effectiveMode}') in ['cool', 'heat', 'off'] }}";
      }
    ];
    actions = [ { action = "script.hvac_mode_handoff"; } ];
  };

  # Record the temperature a room started at, so progress can be measured
  # without depending on a statistics or derivative integration.
  # Compressor protection rides on timers rather than the climate entity's
  # last_changed, which resets every time Home Assistant restarts and would
  # otherwise freeze every room for the minimum off time after each deploy.
  # Timers restore across restarts, so they measure the real interval.
  transitionAutomation = {
    alias = "HVAC record transitions";
    description = "Snapshot the starting temperature and run the minimum run/off timers.";
    mode = "queued";
    triggers = lib.concatMap (room: [
      {
        trigger = "state";
        entity_id = climateEntity room;
        to = "cool";
        id = "${room}_cool";
      }
      {
        trigger = "state";
        entity_id = climateEntity room;
        to = "heat";
        id = "${room}_cool";
      }
      {
        trigger = "state";
        entity_id = climateEntity room;
        to = "off";
        id = "${room}_off";
      }
    ]) roomNames;
    actions = [
      {
        choose = lib.concatMap (room: [
          {
            conditions = [
              {
                condition = "trigger";
                id = "${room}_cool";
              }
            ];
            sequence = [
              {
                action = "input_number.set_value";
                target.entity_id = startTempNumber room;
                data.value = "{{ states('${tempSensor room}') | float(0) | round(1) }}";
              }
              {
                action = "timer.start";
                target.entity_id = minRunTimer room;
                data.duration = tuning.minRunMinutes * 60;
              }
            ];
          }
          {
            conditions = [
              {
                condition = "trigger";
                id = "${room}_off";
              }
            ];
            sequence = [
              {
                action = "timer.start";
                target.entity_id = minOffTimer room;
                data.duration = tuning.minOffMinutes * 60;
              }
            ];
          }
        ]) roomNames;
      }
    ];
  };

  # Drafts are initialized once and then restored, never synchronized over
  # edits. Keep existing applied helpers/timers intact during this migration.
  sliderSyncAutomation = {
    alias = "HVAC initialize override drafts";
    mode = "single";
    triggers = [
      {
        trigger = "homeassistant";
        event = "start";
      }
      {
        trigger = "state";
        entity_id = map targetSensor roomNames ++ map heatTargetSensor roomNames;
      }
    ];
    conditions = [
      {
        condition = "state";
        entity_id = "input_boolean.hvac_drafts_initialized";
        state = "off";
      }
      {
        condition = "template";
        value_template = "{{ ${
          lib.concatMapStringsSep " and " (
            room: "is_number(states('${targetSensor room}')) and is_number(states('${heatTargetSensor room}'))"
          ) roomNames
        } }}";
      }
    ];
    actions =
      (map (room: {
        action = "input_number.set_value";
        target.entity_id = draftNumber room;
        data.value = "{{ states('${heatTargetSensor room}') | float(68) if is_state('${effectiveMode}', 'heat') else states('${targetSensor room}') | float(75) }}";
      }) roomNames)
      ++ (map (room: {
        action = "{{ 'input_boolean.turn_off' if is_state('${overrideTimer room}', 'active') and is_state('${enableToggle room}', 'off') else 'input_boolean.turn_on' }}";
        target.entity_id = draftEnable room;
      }) roomNames)
      ++ [
        {
          action = "input_select.select_option";
          target.entity_id = draftMode;
          data.option = "{{ states('${overrideMode}') if (${anyOverrideActive}) else '${followSystem}' }}";
        }
        {
          action = "input_boolean.turn_on";
          target.entity_id = "input_boolean.hvac_drafts_initialized";
        }
      ];
  };

  patienceTemplate = ''
    {%- if mode != 'cool' or not outdoor_fresh or not is_number(outdoor_value) or outdoor_unit not in ['°F', '°C'] -%}1
    {%- else -%}
      {%- set outside = (outdoor_value | float) * 1.8 + 32 if outdoor_unit == '°C' else outdoor_value | float -%}
      {{ 1 + [[(outside - sample) / ${toString tuning.deltaForDoubleWait}, 0] | max, 1] | min }}
    {%- endif -%}'';

  # Pure decision template, exercised by the offline regression suite. Progress
  # refreshes the observation window, never the per-cycle retry budget.
  # Starts get two blind resends before temperature can show anything.
  # A dark sensor cannot confirm a stop, and it rides the same blaster that
  # drops, so the off ladder walks blind rather than stalling on stale data.
  # A missed off is harmless when the room is about to restart in that mode.
  watchDecision = ''
    {%- if mode == 'off' and phase in ['off_pending', 'off_check', 'off_final', 'off_failed'] and desired == last_run -%}wait
    {%- elif phase == 'off_pending' -%}
      {{ 'off_retry' if mode == 'off' and elapsed >= 120 else 'wait' }}
    {%- elif mode == 'off' and phase in ['off_check', 'off_final', 'off_failed'] and fresh -%}
      {%- if stop_boundary <= -40 -%}off_rebase
      {%- elif elapsed < 300 -%}wait
      {%- elif off_drift >= 0.5 and off_overshoot -%}
        {{ 'off_correct' if phase == 'off_check' else ('off_recover' if phase == 'off_failed' else 'off_failed') }}
      {%- elif off_overshoot and off_drift > 0 and elapsed < 7200 -%}off_accumulate
      {%- else -%}off_observe
      {%- endif -%}
    {%- elif mode == 'off' and phase in ['off_check', 'off_final'] -%}
      {{ 'wait' if elapsed < 300 else ('off_correct' if phase == 'off_check' else 'off_failed') }}
    {%- elif mode not in ['cool', 'heat'] or desired != mode or not fresh -%}wait
    {%- elif phase == 'idle' or checkpoint <= 0 -%}initialize
    {%- elif phase == 'starting' and elapsed < 300 -%}
      {{ 'confirm' if elapsed >= 60 and recovery_elapsed >= 110 else 'wait' }}
    {%- elif elapsed < 300 -%}wait
    {%- elif progress >= ${toString tuning.progressDegrees} -%}progress
    {%- elif not unmet -%}progress
    {%- elif phase in ['starting', 'watching'] -%}retry
    {%- elif phase == 'retried' and elapsed >= ${toString tuning.boostMinutes} * patience * 60 -%}boost
    {%- elif phase == 'boosted' and elapsed >= ${toString tuning.stallMinutes} * patience * 60 -%}stall
    {%- elif phase in ['retried', 'boosted', 'stalled', 'exhausted', 'settled'] and recovery_elapsed >= 170 -%}recover
    {%- else -%}wait
    {%- endif -%}'';

  # Compare five-minute means, not single noisy readings. While off, retain
  # a baseline for up to two hours when drifting farther past the stop boundary.
  # off_accumulate deliberately changes neither the baseline nor checkpoint:
  # small drops/rises must add up rather than disappear every five minutes.
  # A corrective send starts a new observation window; flat/reversing trends
  # rebase normally, so an old temperature difference cannot cause timed beeps.
  # All budgets and
  # checkpoints restore across HA restarts; no startup command storm.
  mkWatchAutomation =
    room:
    let
      phaseEntity = "input_select.hvac_watch_${room}";
      checkpointEntity = "input_number.hvac_checkpoint_${room}";
      recordRecovery = {
        action = "input_number.set_value";
        target.entity_id = "input_number.hvac_last_recovery_${room}";
        data.value = "{{ as_timestamp(now()) }}";
      };
      baselineEntity = "input_number.hvac_baseline_${room}";
      captureBoundary = {
        action = "input_number.set_value";
        target.entity_id = "input_number.hvac_stop_boundary_${room}";
        data.value = "{{ (states('${targetSensor room}') | float(75)) - ${toString tuning.hysteresis} if mode == 'cool' or (mode == 'off' and last_run == 'cool') else (states('${heatTargetSensor room}') | float(68)) + ${toString tuning.hysteresis} }}";
      };
      dismissWarning = {
        action = "persistent_notification.dismiss";
        data.notification_id = "hvac_off_${room}";
      };
      setPhase = option: {
        action = "input_select.select_option";
        target.entity_id = phaseEntity;
        data = { inherit option; };
      };
      checkpoint = [
        {
          action = "input_number.set_value";
          target.entity_id = baselineEntity;
          data.value = "{{ sample }}";
        }
        {
          action = "input_number.set_value";
          target.entity_id = checkpointEntity;
          data.value = "{{ as_timestamp(now()) }}";
        }
      ];
    in
    {
      alias = "HVAC ${rooms.${room}} progress watch";
      mode = "queued";
      max = 5;
      triggers = [
        {
          trigger = "time_pattern";
          minutes = "/1";
          id = "tick";
        }
        {
          trigger = "state";
          entity_id = climateEntity room;
          to = null;
          id = "transition";
        }
      ];
      # Record transitions even while an override is committing. Only the
      # periodic command path waits for the commit to finish.
      conditions = [
        {
          condition = "template";
          value_template = "{{ trigger.id == 'transition' or is_state('script.hvac_apply_override', 'off') }}";
        }
      ];
      actions = [
        {
          variables = {
            mode = "{{ states('${climateEntity room}') }}";
            desired = desiredTemplate room;
            phase = "{{ states('${phaseEntity}') }}";
            last_run = "{{ states('input_select.hvac_last_run_${room}') }}";
            stop_boundary = "{{ states('input_number.hvac_stop_boundary_${room}') | float(-40) }}";
            checkpoint = "{{ states('${checkpointEntity}') | float(0) }}";
            sample = "{{ states('sensor.hvac_mean_${room}') | float(states('${tempSensor room}') | float(0)) }}";
            fresh = "{{ is_number(states('${tempSensor room}')) and is_number(states('sensor.hvac_mean_${room}')) and (as_timestamp(now()) - as_timestamp(states.sensor.ac_controller_${room}_temperature.last_reported, 0)) < 300 }}";
            outdoor_value = "{{ state_attr('${tuning.outdoorEntity}', 'temperature') }}";
            outdoor_unit = "{{ state_attr('${tuning.outdoorEntity}', 'temperature_unit') }}";
            outdoor_fresh = "{{ states('${tuning.outdoorEntity}') not in ['unknown', 'unavailable'] and (as_timestamp(now()) - as_timestamp(states['${tuning.outdoorEntity}'].last_updated, 0)) < 3600 }}";
          };
        }
        {
          variables = {
            elapsed = "{{ as_timestamp(now()) - checkpoint }}";
            progress = "{{ ((states('${baselineEntity}') | float(sample)) - sample) * (1 if mode == 'cool' else -1) }}";
            patience = patienceTemplate;
            recovery_elapsed = "{{ as_timestamp(now()) - (states('input_number.hvac_last_recovery_${room}') | float(0)) }}";
            unmet = "{{ (mode == 'cool' and sample > (states('${targetSensor room}') | float(999))) or (mode == 'heat' and sample < (states('${heatTargetSensor room}') | float(-999))) }}";
            off_drift = "{{ ((states('${baselineEntity}') | float(sample)) - sample) * (1 if last_run == 'cool' else -1) }}";
            off_overshoot = "{{ (last_run == 'cool' and sample < stop_boundary - 1) or (last_run == 'heat' and sample > stop_boundary + 1) }}";
          };
        }
        {
          choose = [
            {
              conditions = "{{ trigger.id == 'transition' and trigger.from_state is not none and trigger.to_state is not none and trigger.from_state.state in ['cool', 'heat', 'off'] and trigger.to_state.state in ['cool', 'heat', 'off'] and trigger.from_state.state != trigger.to_state.state }}";
              sequence = [
                (setPhase "{{ 'off_pending' if mode == 'off' else 'starting' }}")
                captureBoundary
                {
                  choose = [
                    {
                      conditions = "{{ mode in ['cool', 'heat'] }}";
                      sequence = [ dismissWarning ];
                    }
                  ];
                }
                {
                  action = "input_select.select_option";
                  target.entity_id = "input_select.hvac_last_run_${room}";
                  data.option = "{{ mode if mode in ['cool', 'heat'] else trigger.from_state.state }}";
                }
              ]
              ++ checkpoint;
            }
          ];
          default = [
            { variables.decision = watchDecision; }
            {
              choose = [
                {
                  conditions = "{{ decision == 'off_retry' }}";
                  sequence = [
                    (setPhase "off_check")
                    (offAction room)
                  ];
                }
                {
                  conditions = "{{ decision in ['off_observe', 'off_rebase'] }}";
                  sequence = [
                    {
                      choose = [
                        {
                          conditions = "{{ decision == 'off_rebase' }}";
                          sequence = [ captureBoundary ];
                        }
                      ];
                    }
                    (setPhase "off_check")
                    dismissWarning
                  ]
                  ++ checkpoint;
                }
                {
                  conditions = "{{ decision == 'off_correct' }}";
                  sequence = [ (setPhase "off_final") ] ++ checkpoint ++ [ (offAction room) ];
                }
                {
                  conditions = "{{ decision in ['off_failed', 'off_recover'] }}";
                  sequence = [
                    (setPhase "off_failed")
                  ]
                  ++ checkpoint
                  ++ [
                    ((offAction room) // { continue_on_error = true; })
                    {
                      action = "persistent_notification.create";
                      data = {
                        notification_id = "hvac_off_${room}";
                        title = "${rooms.${room}} AC may still be running";
                        message = "{{ 'Temperature is still moving past the stop threshold after off retries.' if fresh else 'The room sensor went offline after the off command, so the stop could not be confirmed and blind retries are exhausted.' }} Check the physical unit and IR blaster. Home Assistant cannot confirm IR reception.";
                      };
                    }
                  ];
                }
                {
                  conditions = "{{ decision == 'initialize' }}";
                  sequence = [
                    captureBoundary
                    dismissWarning
                    (setPhase "watching")
                    {
                      action = "input_select.select_option";
                      target.entity_id = "input_select.hvac_last_run_${room}";
                      data.option = "{{ mode }}";
                    }
                  ]
                  ++ checkpoint;
                }
                {
                  conditions = "{{ decision == 'progress' }}";
                  sequence = [
                    (setPhase "{{ 'settled' if phase in ['stalled', 'exhausted'] else ('watching' if phase == 'starting' else phase) }}")
                  ]
                  ++ checkpoint;
                }
                {
                  conditions = "{{ decision in ['confirm', 'retry', 'recover'] }}";
                  # Rate-limit delivery attempts without resetting observation
                  # windows or replenishing the fan/shedding escalation budget.
                  sequence = [
                    recordRecovery
                    {
                      choose = [
                        {
                          conditions = "{{ decision == 'retry' }}";
                          sequence = [ (setPhase "retried") ] ++ checkpoint;
                        }
                      ];
                    }
                  ]
                  ++ [
                    {
                      action = "climate.set_temperature";
                      target.entity_id = climateEntity room;
                      data = {
                        hvac_mode = "{{ mode }}";
                        temperature = "{{ state_attr('${climateEntity room}', 'temperature') }}";
                      };
                    }
                  ];
                }
                {
                  conditions = "{{ decision == 'boost' }}";
                  sequence = [ (setPhase "boosted") ] ++ checkpoint;
                }
                {
                  conditions = "{{ decision == 'stall' }}";
                  sequence = [ (setPhase "stalled") ];
                }
              ];
            }
          ];
        }
      ];
    };

  stalledExpr = room: ''
    (is_state('${climateEntity room}', 'cool')
     and is_state('input_select.hvac_watch_${room}', 'stalled')
     and (states('${tempSensor room}') | float(0)) > (states('${targetSensor room}') | float(999))
     and (as_timestamp(now()) - as_timestamp(states.sensor.ac_controller_${room}_temperature.last_reported, 0)) < 300)
  '';

  # Capacity guard. When the most important calling room stops making progress
  # the outdoor unit has nothing left to give, so take load off the least
  # important room that is running and let the capacity go where it matters.
  shedAutomation = {
    alias = "HVAC capacity shed";
    description = "Shed low-priority rooms when the priority room stops cooling down.";
    mode = "single";
    conditions = [ commitIdle ];
    triggers = [
      {
        trigger = "time_pattern";
        minutes = "/5";
      }
    ];
    actions = [
      {
        variables = {
          stalled = ''
            {% set ns = namespace(pick = "", best = -1) %}
            ${lib.concatMapStrings (room: ''
              {% if ${stalledExpr room} and (states('${prioritySensor room}') | int(0)) > ns.best %}
                {% set ns.pick = '${room}' %}
                {% set ns.best = states('${prioritySensor room}') | int(0) %}
              {% endif %}
            '') roomNames}
            {{ ns.pick }}'';
          victim = ''
            {% set ns = namespace(pick = "", worst = 999) %}
            ${lib.concatMapStrings (room: ''
              {% if is_state('${climateEntity room}', 'cool')
                    and not is_state('${shedTimer room}', 'active')
                    and not is_state('${minRunTimer room}', 'active')
                    and (states('${prioritySensor room}') | int(0)) < (states('sensor.hvac_priority_' ~ (stalled | trim)) | int(0))
                    and (states('${prioritySensor room}') | int(0)) < ns.worst %}
                {% set ns.pick = '${room}' %}
                {% set ns.worst = states('${prioritySensor room}') | int(0) %}
              {% endif %}
            '') roomNames}
            {{ ns.pick }}'';
        };
      }
      {
        choose = [
          {
            conditions = [
              {
                condition = "template";
                value_template = "{{ stalled | trim and victim | trim and (victim | trim) != (stalled | trim) }}";
              }
            ];
            sequence = [
              {
                action = "timer.start";
                target.entity_id = "{{ 'timer.hvac_shed_' ~ (victim | trim) }}";
                data.duration = tuning.shedMinutes * 60;
              }
              {
                action = "input_select.select_option";
                target.entity_id = "{{ 'input_select.hvac_watch_' ~ (stalled | trim) }}";
                data.option = "exhausted";
              }
            ];
          }
        ];
      }
    ];
  };
  # Auto only moves the shared unit after the need has lasted and the last
  # switch is old enough. A max run pauses the clock, since it is deliberate.
  autoSideAutomation =
    let
      stamp = entity: {
        action = "input_number.set_value";
        target.entity_id = entity;
        data.value = "{{ as_timestamp(now()) | int }}";
      };
      clear = {
        action = "input_number.set_value";
        target.entity_id = autoWantSince;
        data.value = 0;
      };
    in
    {
      alias = "HVAC auto side";
      description = "In auto, hand the shared unit to the side the most important room needs.";
      mode = "single";
      triggers = [
        {
          trigger = "time_pattern";
          minutes = "/1";
        }
        {
          trigger = "state";
          entity_id = systemMode;
          to = "auto";
          id = "entered";
        }
      ];
      conditions = [ commitIdle ];
      actions = [
        {
          variables = {
            requested = "{{ states('${requestedMode}') }}";
            want = autoSwitchTemplate;
            since = "{{ states('${autoWantSince}') | float(0) }}";
            switched = "{{ states('${autoSwitchedAt}') | float(0) }}";
          };
        }
        {
          choose = [
            # Start from whatever was running rather than a stale side.
            {
              conditions = "{{ trigger.id == 'entered' and trigger.from_state.state in ['cool', 'heat'] }}";
              sequence = [
                {
                  action = "input_select.select_option";
                  target.entity_id = autoSide;
                  data.option = "{{ trigger.from_state.state }}";
                }
                clear
              ];
            }
            {
              conditions = "{{ requested != 'auto' or (${anyMaxActive}) or not want }}";
              sequence = [ clear ];
            }
            {
              conditions = "{{ since <= 0 }}";
              sequence = [ (stamp autoWantSince) ];
            }
            {
              conditions = "{{ as_timestamp(now()) - since >= ${toString (tuning.autoPersistMinutes * 60)} and as_timestamp(now()) - switched >= ${toString (tuning.autoGuardMinutes * 60)} }}";
              sequence = [
                {
                  action = "input_select.select_option";
                  target.entity_id = autoSide;
                  data.option = "{{ 'heat' if is_state('${autoSide}', 'cool') else 'cool' }}";
                }
                (stamp autoSwitchedAt)
                clear
              ];
            }
          ];
        }
      ];
    };

  roomStatus = room: ''
    {%- set m = states('${effectiveMode}') -%}
    {%- set active = is_state('${overrideTimer room}', 'active') -%}
    {%- set desired -%}${desiredTemplate room}{%- endset -%}
    {%- set running = states('${climateEntity room}') -%}
    ${preemptedTemplate room}
    {%- if is_state('${maxTimer room}', 'active') -%}Max {{ m }}
    {%- elif not is_number(states('${tempSensor room}')) -%}Sensor unavailable
    {%- elif (as_timestamp(now()) - as_timestamp(states.sensor.ac_controller_${room}_temperature.last_reported, 0)) > ${
      toString (tuning.staleMinutes * 60)
    } -%}Sensor stale
    {%- elif is_state('input_select.hvac_watch_${room}', 'off_failed') -%}Check unit: shutdown unconfirmed
    {%- elif desired | trim == 'off' and running in ['cool', 'heat'] and is_state('${minRunTimer room}', 'active') -%}
      {%- set finish = as_timestamp(state_attr('${minRunTimer room}', 'finishes_at'), 0) -%}
      {{ 'Cooling' if running == 'cool' else 'Heating' }} stop pending · minimum run time{% if finish > 0 %}: {{ ([0, finish - as_timestamp(now())] | max / 60) | round(0, 'ceil') | int }}m remaining{% endif %}
    {%- elif active and is_state('${enableToggle room}', 'off') -%}Paused by override
    {%- elif is_state('${shedTimer room}', 'active') -%}Paused for capacity
    {%- elif preempted -%}Paused for max {{ m }} in another room
    {%- elif is_state('${requestedMode}', 'auto') and states('${needSensor room}') in ['cool', 'heat'] and states('${needSensor room}') != m -%}Needs {{ states('${needSensor room}') }} · waiting for auto to switch
    {%- elif m == 'off' -%}System off
    {%- elif is_state('${climateEntity room}', 'off') and is_state('${minOffTimer room}', 'active') -%}
      {%- set finish = as_timestamp(state_attr('${minOffTimer room}', 'finishes_at'), 0) -%}
      Waiting to restart · compressor protection{% if finish > 0 %}: {{ ([0, finish - as_timestamp(now())] | max / 60) | round(0, 'ceil') | int }}m remaining{% endif %}
    {%- elif states('input_select.hvac_watch_${room}') in ['stalled', 'exhausted'] and states('${climateEntity room}') in ['cool', 'heat'] -%}Not reaching target
    {%- else -%}{{ 'Override' if active else 'Following schedule' }}
    {%- endif -%}'';

  # Display the last commanded operating state, separately from its source and
  # diagnostic warnings. IR provides no physical running-state acknowledgement.
  roomActivity = room: ''
    {%- set current = states('${climateEntity room}') -%}
    {%- set enabled = not is_state('${overrideTimer room}', 'active') or not is_state('${enableToggle room}', 'off') -%}
    {%- if current == 'cool' -%}Cooling
    {%- elif current == 'heat' -%}Heating
    {%- elif current != 'off' -%}Unavailable
    {%- elif states('${effectiveMode}') in ['cool', 'heat'] and enabled -%}Idle
    {%- else -%}Off
    {%- endif -%}'';

  # Each room card carries everything for its room, so nothing needs a
  # separate room picker. The system card above them owns the shared mode.
  roomIcons = {
    office = "mdi:desk";
    bedroom = "mdi:bed";
    living_room = "mdi:sofa";
  };

  dashboard = {
    title = "Climate";
    views = [
      {
        title = "Rooms";
        path = "climate";
        icon = "mdi:home-thermometer";
        type = "sections";
        max_columns = 3;
        sections = [
          {
            type = "grid";
            column_span = 3;
            cards = [
              {
                type = "custom:hvac-system-card";
                persist_minutes = tuning.autoPersistMinutes;
                guard_minutes = tuning.autoGuardMinutes;
                grid_options.columns = "full";
              }
            ];
          }
        ]
        ++ map (room: {
          type = "grid";
          cards = [
            (
              {
                type = "custom:hvac-room-card";
                inherit room;
                icon = roomIcons.${room};
                gap = tuning.autoGap;
                max_minutes = tuning.maxMinutes;
                grid_options.columns = 12;
              }
              // lib.optionalAttrs (room == "bedroom") {
                nap = {
                  heat = sleeping.bedroom.heatBelow;
                  cool = sleeping.bedroom.coolAbove;
                };
              }
            )
          ];
        }) roomNames;
      }
      {
        title = "Settings";
        path = "settings";
        icon = "mdi:tune";
        type = "sections";
        max_columns = 3;
        sections = [
          {
            type = "grid";
            column_span = 3;
            cards = [
              {
                type = "markdown";
                content = "Normal fan and airflow apply whenever a room isn't on Max, a hold or a nap. Schedule follows each block's own setting.";
              }
            ];
          }
        ]
        ++ map (room: {
          type = "grid";
          cards = [
            {
              type = "entities";
              title = rooms.${room};
              entities = [
                {
                  entity = fanSelect room;
                  name = "Normal fan";
                }
                {
                  entity = airflowSelect room;
                  name = "Normal airflow";
                }
              ];
            }
          ];
        }) roomNames;
      }
    ];
  };

  dashboardFile = (pkgs.formats.yaml { }).generate "hvac-dashboard.yaml" dashboard;
  configDir = config.services.home-assistant.configDir;
in
{
  # Lovelace resolves a YAML dashboard's filename inside the config directory,
  # which is writable state, so link the generated file into place.
  systemd.services.home-assistant.preStart = lib.mkBefore ''
    ln -sfn ${dashboardFile} ${lib.escapeShellArg configDir}/hvac-dashboard.yaml
  '';

  # The module builds the resource URL from pname and version, so both have to
  # exist on the derivation; the content hash doubles as the cache buster.
  services.home-assistant.extraComponents = [ "statistics" ];

  services.home-assistant.customLovelaceModules = [
    (
      let
        pname = "hvac-controls";
        version = builtins.substring 0 12 (builtins.hashFile "sha256" ./hvac-controls.js);
      in
      pkgs.runCommand "${pname}-${version}" { passthru = { inherit pname version; }; } ''
        mkdir -p $out
        cp ${./hvac-controls.js} $out/${pname}.js
      ''
    )
  ];

  # input_number and timer arrive with default_config, and template has no
  # dependencies of its own, so none of this needs extraComponents.
  services.home-assistant.config = {
    lovelace.dashboards.hvac-yaml = {
      mode = "yaml";
      title = "Climate";
      icon = "mdi:air-conditioner";
      filename = "hvac-dashboard.yaml";
      show_in_sidebar = true;
    };

    sensor = map (room: {
      platform = "statistics";
      name = "hvac_mean_${room}";
      unique_id = "hvac_mean_${room}";
      entity_id = tempSensor room;
      state_characteristic = "mean";
      max_age.minutes = 5;
      sampling_size = 300;
      precision = 2;
    }) roomNames;

    input_number =
      (lib.listToAttrs (
        lib.concatMap (room: [
          {
            name = "hvac_override_${room}";
            value = {
              name = "${rooms.${room}} override cool above";
              min = 60;
              max = 86 + tuning.autoGap;
              step = 1;
              unit_of_measurement = "°F";
              mode = "slider";
              icon = "mdi:thermometer";
            };
          }
          {
            name = "hvac_override_heat_${room}";
            value = {
              name = "${rooms.${room}} override heat below";
              min = 60 - tuning.autoGap;
              max = 86;
              step = 1;
              unit_of_measurement = "°F";
              mode = "slider";
              icon = "mdi:thermometer";
            };
          }
          {
            name = "hvac_draft_${room}";
            value = {
              name = "${rooms.${room}} pending threshold";
              min = 60;
              max = 86;
              step = 1;
              unit_of_measurement = "°F";
              mode = "slider";
              icon = "mdi:thermometer";
            };
          }
          {
            name = "hvac_last_recovery_${room}";
            value = {
              name = "${rooms.${room}} last run recovery attempt";
              min = 0;
              max = 4102444800;
              step = 1;
              mode = "box";
            };
          }
          {
            name = "hvac_checkpoint_${room}";
            value = {
              name = "${rooms.${room}} progress checkpoint";
              min = 0;
              max = 4102444800;
              step = 1;
              mode = "box";
            };
          }
          {
            name = "hvac_stop_boundary_${room}";
            value = {
              name = "${rooms.${room}} stop boundary for monitored run";
              min = -40;
              max = 150;
              step = 0.1;
              mode = "box";
            };
          }
          {
            name = "hvac_baseline_${room}";
            value = {
              name = "${rooms.${room}} progress baseline";
              min = -40;
              max = 150;
              step = 0.01;
              mode = "box";
            };
          }
          {
            name = "hvac_start_temp_${room}";
            value = {
              name = "${rooms.${room}} start temperature";
              min = 0;
              max = 120;
              step = 0.1;
              unit_of_measurement = "°F";
              mode = "box";
              icon = "mdi:thermometer-chevron-down";
            };
          }
        ]) roomNames
      ))
      // {
        hvac_override_minutes = {
          name = "Override duration";
          min = 30;
          max = 480;
          step = 30;
          unit_of_measurement = "min";
          mode = "slider";
          icon = "mdi:timer-outline";
        };
        hvac_nap_minutes = {
          name = "Nap duration";
          min = 20;
          max = 240;
          step = 10;
          unit_of_measurement = "min";
          mode = "slider";
          icon = "mdi:power-sleep";
        };
        hvac_auto_want_since = {
          name = "Auto switch wanted since";
          min = 0;
          max = 4102444800;
          step = 1;
          mode = "box";
        };
        hvac_auto_switched_at = {
          name = "Auto last switched";
          min = 0;
          max = 4102444800;
          step = 1;
          mode = "box";
        };
      };

    # Expiry is the point: when a timer finishes the schedule silently resumes,
    # so an override cannot be left on by accident.
    timer = lib.listToAttrs (
      lib.concatMap (room: [
        {
          name = "hvac_override_${room}";
          value = {
            name = "${rooms.${room}} override";
            duration = "01:00:00";
            restore = true;
          };
        }
        {
          name = "hvac_shed_${room}";
          value = {
            name = "${rooms.${room}} shed";
            duration = "00:${toString tuning.shedMinutes}:00";
            restore = true;
          };
        }
        {
          name = "hvac_min_run_${room}";
          value = {
            name = "${rooms.${room}} minimum run";
            duration = "00:${toString tuning.minRunMinutes}:00";
            restore = true;
          };
        }
        {
          name = "hvac_min_off_${room}";
          value = {
            name = "${rooms.${room}} minimum off";
            duration = "00:${toString tuning.minOffMinutes}:00";
            restore = true;
          };
        }
        {
          name = "hvac_max_${room}";
          value = {
            name = "${rooms.${room}} max run";
            duration = "00:${toString tuning.maxMinutes}:00";
            restore = true;
          };
        }
      ]) roomNames
    );

    # One system-wide mode, because the heads share an outdoor unit and cannot
    # run opposing ones. The per-room toggles are the temporary "not this room"
    # switch; they read as enabled unless explicitly off, so a room is never
    # left out just because its toggle has never been touched.
    # hvac_system_mode is the seasonal baseline. hvac_override_mode holds the
    # applied mode and is ignored when no override timer is active. The fan
    # selects default to following the schedule.
    input_select = {
      hvac_draft_mode = {
        name = "Pending mode (whole system)";
        options = [
          followSystem
          "cool"
          "heat"
          "off"
        ];
        icon = "mdi:hvac";
      };

      hvac_system_mode = {
        name = "Normal mode";
        options = [
          "cool"
          "heat"
          "auto"
          "off"
        ];
        icon = "mdi:hvac";
      };
      hvac_auto_side = {
        name = "Auto side";
        options = [
          "cool"
          "heat"
        ];
        icon = "mdi:hvac";
      };
      hvac_override_mode = {
        name = "Override mode";
        options = [
          followSystem
          "cool"
          "heat"
          "off"
        ];
        icon = "mdi:hvac";
      };
      hvac_max_mode = {
        name = "Max mode";
        options = [
          "cool"
          "heat"
        ];
        icon = "mdi:fan-plus";
      };
    }
    // (lib.listToAttrs (
      lib.concatMap (room: [
        {
          name = "hvac_last_run_${room}";
          value = {
            name = "${rooms.${room}} last run mode";
            options = [
              "unknown"
              "cool"
              "heat"
            ];
          };
        }
        {
          name = "hvac_watch_${room}";
          value = {
            name = "${rooms.${room}} progress watch";
            options = [
              "idle"
              "starting"
              "watching"
              "retried"
              "boosted"
              "stalled"
              "exhausted"
              "settled"
              "off_pending"
              "off_check"
              "off_final"
              "off_failed"
            ];
          };
        }
        {
          name = "hvac_draft_fan_${room}";
          value = {
            name = "${rooms.${room}} pending fan";
            options = fanOptions;
          };
        }
        {
          name = "hvac_draft_airflow_${room}";
          value = {
            name = "${rooms.${room}} pending airflow";
            options = airflowOptions;
          };
        }
        {
          name = "hvac_override_fan_${room}";
          value = {
            name = "${rooms.${room}} override fan";
            options = fanOptions;
          };
        }
        {
          name = "hvac_override_airflow_${room}";
          value = {
            name = "${rooms.${room}} override airflow";
            options = airflowOptions;
          };
        }

        {
          name = "hvac_fan_${room}";
          value = {
            name = "${rooms.${room}} fan";
            options = fanOptions;
            icon = "mdi:fan";
          };
        }
        {
          name = "hvac_airflow_${room}";
          value = {
            name = "${rooms.${room}} airflow";
            options = airflowOptions;
            icon = "mdi:weather-windy";
          };
        }
      ]) roomNames
    ));

    # What the active override is, in words, for the room card.
    input_text = lib.listToAttrs (
      map (room: {
        name = "hvac_override_label_${room}";
        value = {
          name = "${rooms.${room}} override label";
          max = 40;
        };
      }) roomNames
    );

    # No initial values: both applied state and pending edits survive restart.
    input_boolean =
      (lib.listToAttrs (
        lib.concatMap (room: [
          {
            name = "hvac_enable_${room}";
            value = {
              name = "${rooms.${room}} applied enabled";
            };
          }
          {
            name = "hvac_draft_enable_${room}";
            value = {
              name = "${rooms.${room}} run during override";
              icon = "mdi:air-conditioner";
            };
          }
        ]) roomNames
      ))
      // {
        hvac_drafts_initialized.name = "HVAC draft initialization complete";
      };

    template = [
      {
        sensor =
          (map (room: {
            name = "hvac_target_${room}";
            unique_id = "hvac_target_${room}";
            unit_of_measurement = "°F";
            icon = "mdi:thermometer-chevron-up";
            state = targetTemplate room;
          }) roomNames)
          ++ (map (room: {
            name = "hvac_heat_target_${room}";
            unique_id = "hvac_heat_target_${room}";
            unit_of_measurement = "°F";
            icon = "mdi:thermometer-chevron-down";
            state = heatTargetTemplate room;
          }) roomNames)
          ++ (map (room: {
            name = "hvac_priority_${room}";
            unique_id = "hvac_priority_${room}";
            icon = "mdi:sort-numeric-variant";
            state = priorityTemplate room;
          }) roomNames)
          ++ (map (room: {
            name = "hvac_activity_${room}";
            unique_id = "hvac_activity_${room}";
            state = roomActivity room;
          }) roomNames)
          ++ (map (room: {
            name = "hvac_status_${room}";
            unique_id = "hvac_status_${room}";
            state = roomStatus room;
          }) roomNames)
          ++ [
            {
              name = "hvac_nap_target";
              unique_id = "hvac_nap_target";
              unit_of_measurement = "°F";
              state = "{{ ${toString sleeping.bedroom.heatBelow} if is_state('${effectiveMode}', 'heat') else ${toString sleeping.bedroom.coolAbove} }}";
            }
            {
              name = "hvac_next_block";
              unique_id = "hvac_next_block";
              state = nextBlockTemplate;
            }
          ]
          ++ [
            {
              name = "hvac_schedule_block";
              unique_id = "hvac_schedule_block";
              icon = "mdi:calendar-clock";
              state = scheduleBlockTemplate;
            }
            {
              name = "hvac_effective_mode";
              unique_id = "hvac_effective_mode";
              icon = "mdi:hvac";
              state = effectiveModeTemplate;
            }
            {
              name = "hvac_requested_mode";
              unique_id = "hvac_requested_mode";
              icon = "mdi:hvac";
              state = requestedModeTemplate;
            }
          ]
          ++ (map (room: {
            name = "hvac_need_${room}";
            unique_id = "hvac_need_${room}";
            icon = "mdi:thermometer-alert";
            state = needTemplate room;
          }) roomNames)
          ++ (map (room: {
            name = "hvac_normal_fan_${room}";
            unique_id = "hvac_normal_fan_${room}";
            state = normalFanTemplate room;
          }) roomNames)
          ++ (map (room: {
            name = "hvac_fan_${room}";
            unique_id = "hvac_fan_${room}";
            icon = "mdi:fan";
            state = fanTemplate room;
          }) roomNames)
          ++ (map (room: {
            name = "hvac_airflow_${room}";
            unique_id = "hvac_airflow_${room}";
            icon = "mdi:weather-windy";
            state = airflowTemplate room;
          }) roomNames);
      }
    ];

    script = {
      # A room on max is about to be sent the new mode, so stopping it first is just noise.
      hvac_mode_handoff =
        let
          unlessMaxed = room: action: {
            choose = [
              {
                conditions = "{{ not is_state('${maxTimer room}', 'active') }}";
                sequence = [ action ];
              }
            ];
          };
        in
        {
          alias = "Stop all heads before changing system mode";
          mode = "restart";
          sequence = [
            {
              repeat = {
                count = 2;
                sequence =
                  (map (room: unlessMaxed room ((offAction room) // { continue_on_error = true; })) roomNames)
                  ++ [
                    { delay.seconds = 2; }
                  ];
              };
            }
          ]
          ++ (map (
            room:
            unlessMaxed room {
              action = "timer.start";
              target.entity_id = minOffTimer room;
              data.duration = tuning.minOffMinutes * 60;
            }
          ) roomNames);
        };

      # All commits are serialized. The room controller waits until this script
      # finishes, so it never acts on a partly copied set of pending values.
      hvac_apply_override = {
        alias = "Apply temperature override";
        icon = "mdi:check";
        mode = "queued";
        max = 10;
        fields = {
          room = {
            description = "office, bedroom, living_room, or all";
            example = "office";
          };
          minutes = {
            description = "Override duration in minutes";
            example = 60;
          };
          operation = {
            description = "apply, resume, or nap";
            example = "apply";
          };
          # The room card passes these directly; without them the drafts apply.
          temperature = {
            description = "Temperature to get the room to";
            example = 72;
          };
          enabled = {
            description = "Whether the room runs during the override";
            example = true;
          };
          fan = {
            description = "Fan during the override, or schedule";
            example = "schedule";
          };
          airflow = {
            description = "Airflow during the override, or schedule";
            example = "schedule";
          };
        };
        sequence = [
          {
            variables = {
              selected_room = "{{ room | default('all') }}";
              op = "{{ operation | default('apply') }}";
              duration = "{{ [[minutes | default(states('input_number.hvac_override_minutes')) | int(60), 20] | max, 480] | min * 60 }}";
            };
          }
          {
            condition = "template";
            value_template = "{{ selected_room in ['all', 'office', 'bedroom', 'living_room'] and op in ['apply', 'resume', 'nap'] and (op != 'nap' or selected_room == 'bedroom') }}";
          }
          {
            condition = "template";
            value_template = "{{ op == 'resume' or temperature is defined or is_state('input_boolean.hvac_drafts_initialized', 'on') }}";
          }
          {
            choose = [
              {
                conditions = "{{ op == 'resume' }}";
                sequence = [
                  {
                    action = "timer.cancel";
                    target.entity_id = "{{ ${builtins.toJSON (map overrideTimer roomNames)} if selected_room == 'all' else ['timer.hvac_override_' ~ selected_room] }}";
                  }
                ];
              }
            ];
            default = [
              {
                condition = "template";
                value_template = "{{ op != 'nap' or states('${effectiveMode}') in ['cool', 'heat'] }}";
              }
              # Snapshot all UI values before changing any live helpers.
              {
                variables = {
                  commit_mode = "{{ states('${draftMode}') if selected_room == 'all' and op == 'apply' else (states('${overrideMode}') if (${anyOverrideActive}) else '${followSystem}') }}";
                }
                // lib.listToAttrs (
                  lib.concatMap (room: [
                    {
                      name = "value_${room}";
                      value = "{{ (temperature | default(states('${draftNumber room}'))) | float(75) }}";
                    }
                    {
                      name = "fan_${room}";
                      value = "{{ fan | default(states('${draftFan room}')) }}";
                    }
                    {
                      name = "airflow_${room}";
                      value = "{{ airflow | default(states('${draftAirflow room}')) }}";
                    }
                    {
                      name = "enabled_${room}";
                      value = "{{ enabled if enabled is defined else is_state('${draftEnable room}', 'on') }}";
                    }
                  ]) roomNames
                );
              }
              # "Get me to N": an explicit mode picks the side, auto picks it
              # from where the room is now. The other side sits autoGap away.
              {
                variables = lib.listToAttrs (
                  map (room: {
                    name = "side_${room}";
                    value = "{%- set req = commit_mode if commit_mode != '${followSystem}' else states('${systemMode}') -%}{{ req if req in ['cool', 'heat'] else ('cool' if states('${tempSensor room}') | float(0) > value_${room} else 'heat') }}";
                  }) roomNames
                );
              }
              {
                action = "input_select.select_option";
                target.entity_id = overrideMode;
                data.option = "{{ commit_mode }}";
              }
            ]
            ++ (map (room: {
              choose = [
                {
                  conditions = "{{ selected_room in ['all', '${room}'] }}";
                  sequence = [
                    {
                      action = "input_number.set_value";
                      target.entity_id = overrideNumber room;
                      data.value = "{{ ${toString sleeping.bedroom.coolAbove} if op == 'nap' else value_${room} + (0 if side_${room} == 'cool' else ${toString tuning.autoGap}) }}";
                    }
                    {
                      action = "input_number.set_value";
                      target.entity_id = overrideHeatNumber room;
                      data.value = "{{ ${toString sleeping.bedroom.heatBelow} if op == 'nap' else value_${room} - (0 if side_${room} == 'heat' else ${toString tuning.autoGap}) }}";
                    }
                    {
                      action = "{{ 'input_boolean.turn_on' if op == 'nap' or enabled_${room} else 'input_boolean.turn_off' }}";
                      target.entity_id = enableToggle room;
                    }
                    {
                      action = "input_text.set_value";
                      target.entity_id = overrideLabel room;
                      data.value = "{{ 'Nap' if op == 'nap' else (('Hold ' ~ (value_${room} | round(0) | int) ~ '°') if enabled_${room} else 'Room off') }}";
                    }
                    {
                      action = "input_select.select_option";
                      target.entity_id = appliedFan room;
                      data.option = "{{ '${sleeping.bedroom.fan}' if op == 'nap' else fan_${room} }}";
                    }
                    {
                      action = "input_select.select_option";
                      target.entity_id = appliedAirflow room;
                      data.option = "{{ '${sleeping.bedroom.airflow}' if op == 'nap' else airflow_${room} }}";
                    }
                    {
                      action = "timer.start";
                      target.entity_id = overrideTimer room;
                      data.duration = "{{ duration }}";
                    }
                  ];
                }
              ];
            }) roomNames);
          }
        ];
      };
      hvac_back_to_schedule = {
        alias = "Resume schedule";
        icon = "mdi:calendar-check";
        sequence = [
          {
            action = "script.hvac_apply_override";
            data.operation = "resume";
          }
        ];
      };
      hvac_start_nap = {
        alias = "Start bedroom nap";
        icon = "mdi:power-sleep";
        fields.minutes = {
          name = "Minutes";
          selector.number = {
            min = 20;
            max = 240;
            step = 10;
          };
        };
        sequence = [
          {
            action = "script.hvac_apply_override";
            data = {
              operation = "nap";
              room = "bedroom";
              minutes = "{{ [[minutes | default(states('input_number.hvac_nap_minutes')) | int(60), 20] | max, 240] | min }}";
            };
          }
        ];
      };
      hvac_end_nap = {
        alias = "Resume bedroom schedule";
        sequence = [
          {
            action = "script.hvac_apply_override";
            data = {
              operation = "resume";
              room = "bedroom";
            };
          }
        ];
      };
      # Each press restarts the window. Switching mode drops rooms still on
      # max in the old one, since the heads cannot run opposing modes.
      hvac_start_max = {
        alias = "Run rooms at max";
        icon = "mdi:fan-plus";
        mode = "queued";
        fields = {
          rooms = {
            description = "Rooms to run: office, bedroom, living_room";
            # HA only accepts string examples; a list here disables the script.
            example = "bedroom";
          };
          hvac_mode = {
            description = "cool or heat";
            example = "cool";
          };
        };
        sequence = [
          {
            variables = {
              selected = "{%- set r = rooms | default([]) -%}{{ ([r] if r is string else r) | select('in', ${builtins.toJSON roomNames}) | list }}";
              max_mode = "{{ hvac_mode | default('') }}";
              mode_changed = "{{ not is_state('${maxMode}', hvac_mode | default('')) }}";
            };
          }
          {
            condition = "template";
            value_template = "{{ selected | count > 0 and max_mode in ['cool', 'heat'] }}";
          }
          {
            action = "input_select.select_option";
            target.entity_id = maxMode;
            data.option = "{{ max_mode }}";
          }
        ]
        ++ map (room: {
          choose = [
            {
              conditions = "{{ '${room}' in selected }}";
              sequence = [
                {
                  action = "timer.cancel";
                  target.entity_id = shedTimer room;
                }
                {
                  action = "timer.start";
                  target.entity_id = maxTimer room;
                  data.duration = tuning.maxMinutes * 60;
                }
              ];
            }
            {
              conditions = "{{ mode_changed }}";
              sequence = [
                {
                  action = "timer.cancel";
                  target.entity_id = maxTimer room;
                }
              ];
            }
          ];
        }) roomNames;
      };
      # Deliberate user action, never background synchronization over a draft.
      hvac_use_current_targets = {
        alias = "Use current thresholds";
        sequence = (
          map (room: {
            action = "input_number.set_value";
            target.entity_id = draftNumber room;
            data.value = "{{ states('${heatTargetSensor room}') | float(68) if is_state('${effectiveMode}', 'heat') else states('${targetSensor room}') | float(75) }}";
          }) roomNames
        );
      };
    };

    "automation manual" =
      (map mkRoomAutomation roomNames)
      ++ (map mkWatchAutomation roomNames)
      ++ [
        transitionAutomation
        modeHandoffAutomation
        sliderSyncAutomation
        shedAutomation
        autoSideAutomation
      ];
  };
}
