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
# re-sends its intent periodically and treats a stale sensor as a reason to
# stop rather than to keep guessing.

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
    # Restate intent this often, since commands are unacknowledged and someone
    # may have picked up the handheld remote.
    reconcileMinutes = 15;
    # A sensor quieter than this is not worth acting on.
    staleMinutes = 15;
    # Capacity shedding: a room cooling this long that has not fallen by at
    # least this much has run into the limits of the outdoor unit.
    stallMinutes = 20;
    stallProgress = 1.0;
    shedMinutes = 30;
    overridePriority = 10;
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

  # heatBelow only applies when the system mode is set to heat. The house does
  # not drop below 68 in practice, so these are placeholders to be revisited
  # before winter rather than numbers anyone has lived with.

  # Fan is a preference, not a throttle. The setpoint already scales output and
  # the unit's own auto varies the fan with information we do not have, so this
  # only departs from auto where noise matters more than speed.

  # Asleep: only the bedroom matters, the rest just must not bake.
  sleeping = {
    bedroom = {
      coolAbove = 73;
      heatBelow = 66;
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
      heatBelow = 66;
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

  scheduleJson = builtins.toJSON schedule;

  tempSensor = room: "sensor.ac_controller_${room}_temperature";
  climateEntity = room: "climate.${room}_ac";
  overrideTimer = room: "timer.hvac_override_${room}";
  shedTimer = room: "timer.hvac_shed_${room}";
  overrideNumber = room: "input_number.hvac_override_${room}";
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

  effectiveModeTemplate = ''
    {%- if (${anyOverrideActive}) and not is_state('${overrideMode}', '${followSystem}') -%}
      {{ states('${overrideMode}') }}
    {%- else -%}
      {{ states('${systemMode}') }}
    {%- endif -%}'';

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
      {{ states('${overrideNumber room}') | float(68) | round(0) }}
    {%- else -%}
      {{ ns.current.rooms['${room}'].heatBelow }}
    {%- endif -%}'';

  priorityTemplate = room: ''
    ${currentBlock}
    {%- if is_state('${overrideTimer room}', 'active') -%}
      ${toString tuning.overridePriority}
    {%- else -%}
      {{ ns.current.rooms['${room}'].priority }}
    {%- endif -%}'';

  fanTemplate = room: ''
    ${currentBlock}
    {%- if is_state('${overrideTimer room}', 'active') and states('${appliedFan room}') in ['auto', 'quiet', '1', '2', '3', '4', '5'] -%}
      {{ states('${appliedFan room}') }}
    {%- elif is_state('${fanSelect room}', '${fanFollowsSchedule}') -%}
      {{ ns.current.rooms['${room}'].fan }}
    {%- else -%}
      {{ states('${fanSelect room}') }}
    {%- endif -%}'';

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
  # on and off around a single number.
  desiredTemplate = room: ''
    {%- set sys = states('${effectiveMode}') -%}
    {%- set enabled = not is_state('${overrideTimer room}', 'active') or not is_state('${enableToggle room}', 'off') -%}
    {%- set r = states('${tempSensor room}') | float(-999) -%}
    {%- set ct = states('${targetSensor room}') | float(999) -%}
    {%- set ht = states('${heatTargetSensor room}') | float(-999) -%}
    {%- set cur = states('${climateEntity room}') -%}
    {%- set blocked = (not enabled) or sys == 'off' or is_state('${shedTimer room}', 'active')
        or states('${tempSensor room}') in ['unknown', 'unavailable']
        or (as_timestamp(now()) - as_timestamp(states.sensor.ac_controller_${room}_temperature.last_reported, 0)) > ${
          toString (tuning.staleMinutes * 60)
        } -%}
    {%- if blocked -%}off
    {%- elif sys == 'cool' -%}
      {{ 'cool' if r > ct else ('off' if r <= ct - ${toString tuning.hysteresis} else cur) }}
    {%- elif sys == 'heat' -%}
      {{ 'heat' if r < ht else ('off' if r >= ht + ${toString tuning.hysteresis} else cur) }}
    {%- else -%}off
    {%- endif -%}'';

  # The gap below (cooling) or above (heating) the threshold scales with how
  # far off the room is, because the head treats its own error as a throttle.
  setpointTemplate = room: ''
    {%- set sys = states('${effectiveMode}') -%}
    {%- set r = states('${tempSensor room}') | float(0) -%}
    {%- if sys == 'heat' -%}
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
    setpoint = setpointTemplate room;
    airflow = "{{ states('${airflowSensor room}') }}";
    current_airflow = "{{ state_attr('${climateEntity room}', 'swing_mode') }}";
    fan = "{{ states('${fanSensor room}') }}";
    current_fan = "{{ state_attr('${climateEntity room}', 'fan_mode') }}";

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
      }
      {
        trigger = "state";
        entity_id = heatTargetSensor room;
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
        entity_id = effectiveMode;
      }
      {
        trigger = "state";
        entity_id = "script.hvac_apply_override";
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
    conditions = [ commitIdle ];
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
          # Start, switch mode, or correct a setpoint that has drifted.
          {
            conditions = [
              {
                condition = "template";
                value_template = ''
                  {{ desired != 'off'
                     and (current_mode != desired
                          or (state_attr('${climateEntity room}', 'temperature') | float(0)) != setpoint)
                     and (current_mode != 'off' or not min_off_active) }}'';
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
                  {{ desired != 'off' and current_mode == desired
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
                  {{ desired != 'off' and current_mode == desired
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

  # Commands are never acknowledged, so restate intent on a slow cycle.
  reconcileAutomation = {
    alias = "HVAC reconcile";
    description = "Re-send the intended state, since IR gives no feedback.";
    mode = "single";
    conditions = [ commitIdle ];
    triggers = [
      {
        trigger = "time_pattern";
        minutes = "/${toString tuning.reconcileMinutes}";
      }
    ];
    # Off is restated too, and that matters more than restating on. A missed
    # off leaves the head running while Home Assistant shows it stopped, with
    # nothing to notice or correct it; that is how a deselected room can heat
    # all night.
    actions = map (room: {
      choose = [
        {
          conditions = [
            {
              condition = "template";
              value_template = "{{ is_state('${climateEntity room}', 'off') }}";
            }
          ];
          sequence = [ (offAction room) ];
        }
      ];
      default = [
        {
          action = "climate.set_temperature";
          target.entity_id = climateEntity room;
          data = {
            hvac_mode = "{{ states('${climateEntity room}') }}";
            temperature = "{{ state_attr('${climateEntity room}', 'temperature') | round(0) }}";
          };
        }
      ];
    }) roomNames;
  };

  # True when a room has been cooling a while without making real headway.
  stalledExpr = room: ''
    (is_state('${climateEntity room}', 'cool')
     and (states('${tempSensor room}') | float(0)) > (states('${targetSensor room}') | float(999))
     and (now() - states.climate.${room}_ac.last_changed).total_seconds() > ${
       toString (tuning.stallMinutes * 60)
     }
     and ((states('${startTempNumber room}') | float(0)) - (states('${tempSensor room}') | float(0))) < ${toString tuning.stallProgress})
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
            ];
          }
        ];
      }
    ];
  };
  activeTimerCard = entity: name: {
    type = "conditional";
    conditions = [
      {
        condition = "state";
        inherit entity;
        state = "active";
      }
    ];
    card = {
      type = "tile";
      inherit entity name;
      icon = "mdi:timer-outline";
    };
    grid_options.columns = 12;
  };
  roomStatus = room: ''
    {%- set m = states('${effectiveMode}') -%}
    {%- set active = is_state('${overrideTimer room}', 'active') -%}
    {%- if not is_number(states('${tempSensor room}')) -%}Sensor unavailable
    {%- elif (as_timestamp(now()) - as_timestamp(states.sensor.ac_controller_${room}_temperature.last_reported, 0)) > ${
      toString (tuning.staleMinutes * 60)
    } -%}Sensor stale
    {%- elif active and is_state('${enableToggle room}', 'off') -%}Paused by override
    {%- elif is_state('${shedTimer room}', 'active') -%}Paused for capacity
    {%- elif m == 'off' -%}System off
    {%- elif is_state('${climateEntity room}', 'off') and is_state('${minOffTimer room}', 'active') -%}Waiting to restart
    {%- else -%}{{ 'Override' if active else 'Following schedule' }}
    {%- endif -%}'';

  # Native sections reflow whole room panels, rather than squeezing three
  # thermostat dials onto a phone. The large numbers are always measurements.
  dashboard = {
    title = "Climate";
    views = [
      {
        title = "Rooms";
        path = "climate";
        icon = "mdi:home-thermometer";
        type = "sections";
        max_columns = 3;
        header = {
          layout = "start";
          card = {
            type = "markdown";
            text_only = true;
            content = ''
              ## Climate
              **{{ states('sensor.hvac_schedule_block') }}** · {{ states('${effectiveMode}') | title }} · Next: {{ states('sensor.hvac_next_block') }}
            '';
          };
        };
        sections =
          (map (room: {
            type = "grid";
            cards = [
              {
                type = "heading";
                heading = rooms.${room};
                heading_style = "title";
                icon =
                  if room == "bedroom" then
                    "mdi:bed"
                  else if room == "office" then
                    "mdi:desk"
                  else
                    "mdi:sofa";
              }
              {
                type = "sensor";
                entity = tempSensor room;
                name = "Temperature";
                graph = "line";
                hours_to_show = 6;
                detail = 1;
                grid_options.columns = 6;
              }
              {
                type = "sensor";
                entity = "sensor.ac_controller_${room}_humidity";
                name = "Humidity";
                graph = "line";
                hours_to_show = 6;
                detail = 1;
                grid_options.columns = 6;
              }
              {
                type = "markdown";
                grid_options.columns = 12;
                content = ''
                  {{ states('sensor.hvac_status_${room}') }} · {% set m = states('${effectiveMode}') %}{% if m == 'heat' %}Heat below **{{ states('${heatTargetSensor room}') }}°F**{% elif m == 'cool' %}Cool above **{{ states('${targetSensor room}') }}°F**{% else %}Off{% endif %}
                '';
              }
              (activeTimerCard (shedTimer room) "Capacity pause")

            ];
          }) roomNames)
          ++ [
            {
              type = "grid";
              column_span = 2;
              cards = [
                {
                  type = "custom:hvac-override-card";
                  grid_options.columns = "full";
                }
              ];
            }
            {
              type = "grid";
              cards = [
                {
                  type = "custom:hvac-nap-card";
                  grid_options.columns = 12;
                }
              ];
            }
          ];
      }
      {
        title = "Settings";
        path = "settings";
        icon = "mdi:tune";
        type = "sections";
        max_columns = 2;
        sections = [
          {
            type = "grid";
            cards = [
              {
                type = "heading";
                heading = "System";
              }
              {
                type = "entities";
                entities = [
                  {
                    entity = systemMode;
                    name = "Normal mode (whole system)";
                  }
                  {
                    entity = effectiveMode;
                    name = "Active mode";
                  }
                ];
              }
              {
                type = "markdown";
                content = "Heating/cooling mode is shared by all rooms. Fan and airflow preferences below are the defaults used when no timed override is active.";
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
    ]
    ++ map (room: {
      title = rooms.${room};
      path = room;
      subview = true;
      cards = [
        {
          type = "entities";
          title = "${rooms.${room}} preferences";
          show_header_toggle = false;
          entities = [
            {
              entity = fanSelect room;
              name = "Fan (applies immediately)";
            }
            {
              entity = airflowSelect room;
              name = "Airflow (applies immediately)";
            }
            {
              entity = fanSensor room;
              name = "Active fan";
            }
            {
              entity = airflowSensor room;
              name = "Active airflow";
            }
          ];
        }
        {
          type = "entities";
          title = "Controller details";
          entities = [
            {
              entity = climateEntity room;
              name = "Last commanded AC state";
            }
            {
              type = "attribute";
              entity = climateEntity room;
              attribute = "temperature";
              name = "Commanded setpoint";
              suffix = "°F";
            }
            {
              entity = prioritySensor room;
              name = "Priority";
            }
          ];
        }
        {
          type = "markdown";
          content = "IR commands have no acknowledgement. The commanded setpoint is adjusted by the controller and is not the room threshold. Direct climate edits are temporary; use the room override controls for lasting changes.";
        }
      ];
    }) roomNames;
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

    input_number =
      (lib.listToAttrs (
        lib.concatMap (room: [
          {
            name = "hvac_override_${room}";
            value = {
              name = "${rooms.${room}} override";
              min = 60;
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
          "off"
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
    }
    // (lib.listToAttrs (
      lib.concatMap (room: [
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
          ]
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
            value_template = "{{ op == 'resume' or is_state('input_boolean.hvac_drafts_initialized', 'on') }}";
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
                  nap_heat = "{{ is_state('${effectiveMode}', 'heat') }}";
                }
                // lib.listToAttrs (
                  lib.concatMap (room: [
                    {
                      name = "value_${room}";
                      value = "{{ states('${draftNumber room}') | float(75) }}";
                    }
                    {
                      name = "fan_${room}";
                      value = "{{ states('${draftFan room}') }}";
                    }
                    {
                      name = "airflow_${room}";
                      value = "{{ states('${draftAirflow room}') }}";
                    }
                    {
                      name = "enabled_${room}";
                      value = "{{ is_state('${draftEnable room}', 'on') }}";
                    }
                  ]) roomNames
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
                      data.value = "{{ (${toString sleeping.bedroom.heatBelow} if nap_heat else ${toString sleeping.bedroom.coolAbove}) if op == 'nap' else value_${room} }}";
                    }
                    {
                      action = "{{ 'input_boolean.turn_on' if op == 'nap' or enabled_${room} else 'input_boolean.turn_off' }}";
                      target.entity_id = enableToggle room;
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

    "automation manual" = (map mkRoomAutomation roomNames) ++ [
      transitionAutomation
      sliderSyncAutomation
      reconcileAutomation
      shedAutomation
    ];
  };
}
