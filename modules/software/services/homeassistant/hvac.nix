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
  roomNames = lib.attrNames rooms;

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
    bedroom = { coolAbove = 71; heatBelow = 66; priority = 10; fan = "quiet"; airflow = "comfort"; };
    office = { coolAbove = 82; heatBelow = 60; priority = 1; fan = "auto"; airflow = "comfort"; };
    living_room = { coolAbove = 82; heatBelow = 60; priority = 1; fan = "auto"; airflow = "comfort"; };
  };

  # Working. Taylor is in the office every day, weekends included.
  working = {
    office = { coolAbove = 76; heatBelow = 68; priority = 10; fan = "auto"; airflow = "comfort"; };
    living_room = { coolAbove = 78; heatBelow = 66; priority = 5; fan = "auto"; airflow = "comfort"; };
    bedroom = { coolAbove = 80; heatBelow = 60; priority = 1; fan = "auto"; airflow = "comfort"; };
  };

  # The bedroom pulls down while the office is still occupied, so it is at
  # temperature on arrival rather than starting from 80. Nobody is in there
  # yet, so it pulls down on auto and only goes quiet once Asleep begins.
  preBed = {
    bedroom = { coolAbove = 71; heatBelow = 66; priority = 10; fan = "auto"; airflow = "comfort"; };
    office = { coolAbove = 76; heatBelow = 68; priority = 5; fan = "auto"; airflow = "comfort"; };
    living_room = { coolAbove = 80; heatBelow = 60; priority = 1; fan = "auto"; airflow = "comfort"; };
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
    {%- if is_state('${airflowSelect room}', '${airflowFollowsSchedule}') -%}
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
      {{ states('${overrideNumber room}') | round(0) }}
    {%- else -%}
      {{ ns.current.rooms['${room}'].coolAbove }}
    {%- endif -%}'';

  heatTargetTemplate = room: ''
    ${currentBlock}
    {%- if is_state('${overrideTimer room}', 'active') -%}
      {{ states('${overrideNumber room}') | round(0) }}
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
    {%- if is_state('${fanSelect room}', '${fanFollowsSchedule}') -%}
      {{ ns.current.rooms['${room}'].fan }}
    {%- else -%}
      {{ states('${fanSelect room}') }}
    {%- endif -%}'';

  # Which block of today's pattern is in force, for the dashboard.
  scheduleBlockTemplate = ''
    ${currentBlock}
    {{- ns.current.label }} since {{ ns.current.from -}}'';

  # Resolve what the room should be doing into one value, so the automation
  # below is "apply this" rather than a tree of cool and heat branches. Holding
  # the current mode inside the hysteresis band is what stops a room chattering
  # on and off around a single number.
  desiredTemplate = room: ''
    {%- set sys = states('${effectiveMode}') -%}
    {%- set enabled = not is_state('${enableToggle room}', 'off') -%}
    {%- set r = states('${tempSensor room}') | float(-999) -%}
    {%- set ct = states('${targetSensor room}') | float(999) -%}
    {%- set ht = states('${heatTargetSensor room}') | float(-999) -%}
    {%- set cur = states('${climateEntity room}') -%}
    {%- set blocked = (not enabled) or sys == 'off' or is_state('${shedTimer room}', 'active')
        or states('${tempSensor room}') in ['unknown', 'unavailable']
        or (as_timestamp(now()) - as_timestamp(states.sensor.ac_controller_${room}_temperature.last_reported, 0)) > ${toString (tuning.staleMinutes * 60)} -%}
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
    # What an idle room's dial shows: its own temperature. The card puts this
    # numeral front and centre, so while the head is off it may as well read
    # the room rather than a setpoint that is not in use. When cooling starts
    # the dial turns blue and switches to the real setpoint, which makes the
    # transition obvious.
    park = "{{ [[states('${tempSensor room}') | float(75), ${toString tuning.setpointFloor}] | max, 86] | min | round(0) }}";
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
      { trigger = "state"; entity_id = tempSensor room; }
      { trigger = "state"; entity_id = targetSensor room; }
      { trigger = "state"; entity_id = heatTargetSensor room; }
      { trigger = "state"; entity_id = shedTimer room; }
      { trigger = "state"; entity_id = effectiveMode; }
      { trigger = "state"; entity_id = enableToggle room; }
      { trigger = "state"; entity_id = airflowSensor room; }

      { trigger = "state"; entity_id = fanSensor room; }
      { trigger = "time_pattern"; minutes = "/1"; }
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
                value_template = ''
                  {{ desired == 'off' and current_mode != 'off' and not min_run_active }}'';
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
          # Idle and staying idle: park the dial on the threshold, so it reads
          # as "cools above this" rather than showing an arbitrary number. With
          # the head off, SmartIR stores the value without transmitting, so
          # this costs no IR and stops a never-commanded room displaying its
          # minimum temperature.
          {
            conditions = [
              {
                condition = "template";
                value_template = ''
                  {{ desired == 'off' and current_mode == 'off'
                     and (state_attr('${climateEntity room}', 'temperature') | float(0)) != park }}'';
              }
            ];
            sequence = [
              {
                action = "climate.set_temperature";
                target.entity_id = climateEntity room;
                data.temperature = "{{ park }}";
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

  # Park each override slider on the threshold actually in force, so opening
  # the dashboard shows the current setting rather than whatever was left
  # behind. The threshold is the useful starting point rather than the room
  # temperature: it is the number being overridden.
  #
  # Only rooms without an active override are touched, so this never fights an
  # override in progress. Writing a value that is already set changes nothing,
  # so there is no feedback loop, and the target sensors only fire on a real
  # change rather than on every re-render.
  sliderSyncAutomation = {
    alias = "HVAC sync override sliders";
    description = "Keep each override slider on the threshold currently in force.";
    mode = "queued";
    triggers =
      (lib.concatMap (room: [
        {
          trigger = "state";
          entity_id = targetSensor room;
        }
        {
          trigger = "state";
          entity_id = overrideTimer room;
          to = "idle";
        }
      ]) roomNames)
      ++ [
        {
          trigger = "state";
          entity_id = effectiveMode;
        }
        {
          trigger = "homeassistant";
          event = "start";
        }
      ];
    actions = (map (room: {
      choose = [
        {
          conditions = [
            {
              condition = "template";
              value_template = "{{ not is_state('${overrideTimer room}', 'active') }}";
            }
          ];
          sequence = [
            {
              action = "input_number.set_value";
              target.entity_id = overrideNumber room;
              # The threshold for whichever mode is running. Parking a cool
              # threshold while in heat would offer 82 as a heat target.
              data.value = ''
                {% if is_state('${effectiveMode}', 'heat') %}{{ states('${heatTargetSensor room}') | float(68) | round(0) }}{% else %}{{ states('${targetSensor room}') | float(75) | round(0) }}{% endif %}'';
            }
          ];
        }
      ];
    }) roomNames)
    ++ [
      {
        # An override is one operation: a mode, a temperature per room, and
        # which rooms take part. All of it has to end together, or excluding a
        # room for half an hour quietly excludes it forever.
        choose = [
          {
            conditions = [
              {
                condition = "template";
                value_template = "{{ not (${anyOverrideActive}) }}";
              }
            ];
            sequence = [
              {
                action = "input_select.select_option";
                target.entity_id = overrideMode;
                data.option = followSystem;
              }
              {
                action = "input_boolean.turn_on";
                target.entity_id = map enableToggle roomNames;
              }
            ];
          }
        ];
      }
    ];
  };

  # Commands are never acknowledged, so restate intent on a slow cycle.
  reconcileAutomation = {
    alias = "HVAC reconcile";
    description = "Re-send the intended state, since IR gives no feedback.";
    mode = "single";
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
     and (now() - states.climate.${room}_ac.last_changed).total_seconds() > ${toString (tuning.stallMinutes * 60)}
     and ((states('${startTempNumber room}') | float(0)) - (states('${tempSensor room}') | float(0))) < ${toString tuning.stallProgress})
  '';

  # Capacity guard. When the most important calling room stops making progress
  # the outdoor unit has nothing left to give, so take load off the least
  # important room that is running and let the capacity go where it matters.
  shedAutomation = {
    alias = "HVAC capacity shed";
    description = "Shed low-priority rooms when the priority room stops cooling down.";
    mode = "single";
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
                value_template = ''
                  {{ stalled | trim and victim | trim and (victim | trim) != (stalled | trim) }}'';
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
  # A second dashboard in YAML mode, so the default one stays UI-editable.
  dashboard = {
    title = "Climate";
    views = [
      {
        title = "Climate";
        path = "climate";
        icon = "mdi:air-conditioner";
        cards = [
          {
            type = "grid";
            columns = 3;
            square = false;
            # The thermostat card puts the setpoint in the big numeral and the
            # room temperature in small print, which is the wrong emphasis for
            # this system. It still looks better than the alternatives built
            # from gauges or markdown, both of which were tried and were worse.
            cards = map (room: {
              type = "thermostat";
              entity = climateEntity room;
              name = rooms.${room};
            }) roomNames;
          }
          {
            # The dials already show each room's temperature, so this answers
            # "why is it doing that": which block is in force, and the
            # threshold each room is holding to under it.
            type = "entities";
            title = "Current schedule";
            # Normal mode lives here, not with the override: it is the seasonal
            # setting you change twice a year, alongside what the schedule is
            # doing right now.
            entities = [
              {
                entity = "sensor.hvac_schedule_block";
                name = "Now";
              }
              {
                entity = systemMode;
                name = "Normal mode";
              }
              {
                entity = effectiveMode;
                name = "Running as";
              }
              { type = "divider"; }
            ]
            ++ (map (room: {
              entity = targetSensor room;
              name = "${rooms.${room}} cool above";
            }) roomNames);
          }
          {
            type = "entities";
            title = "Override";
            # The header toggle would flip every switch on this card at once,
            # which is never what anyone means here.
            show_header_toggle = false;
            # Read top to bottom as one operation: which mode, then each room
            # with its switch beside its temperature, then how long, then
            # Apply. Everything here reverts together when the timer ends.
            entities = [
              {
                entity = overrideMode;
                name = "Mode";
              }
              { type = "divider"; }
            ]
            ++ (lib.concatMap (room: [
              {
                entity = enableToggle room;
                name = "${rooms.${room}}";
              }
              {
                entity = overrideNumber room;
                name = " above";
              }
            ]) roomNames)
            ++ [
              { type = "divider"; }
              { entity = "input_number.hvac_override_minutes"; name = "For how long"; }
              { entity = "script.hvac_apply_override"; name = "Apply"; }
              { entity = "script.hvac_back_to_schedule"; name = "Back to schedule"; }
              { type = "divider"; }
            ]
            ++ (map (room: {
              entity = overrideTimer room;
              name = "${rooms.${room}} remaining";
            }) roomNames);
          }
          {
            type = "entities";
            title = "Nap";
            entities = [
              { entity = "input_number.hvac_nap_minutes"; name = "Nap length"; }
              { entity = "script.hvac_start_nap"; name = "Start nap"; }
              { entity = "script.hvac_end_nap"; name = "End nap"; }
              { entity = overrideTimer "bedroom"; name = "Bedroom remaining"; }
            ];
          }
          {
            type = "entities";
            title = "Fan and airflow";
            show_header_toggle = false;
            # Standing preferences, not part of an override. Fan defaults to
            # following the schedule; pin it to hold a speed. Comfort aims the
            # flap away from the room and swing sweeps it, so they are
            # mutually exclusive and comfort wins if both are on.
            entities = lib.concatMap (room: [
              {
                entity = fanSelect room;
                name = "${rooms.${room}} fan";
              }
              {
                entity = airflowSelect room;
                name = "${rooms.${room}} airflow";
              }
              { type = "divider"; }
            ]) roomNames;
          }
          {
            # Shedding is rare, so the card only appears while it is happening
            # rather than sitting there reading Idle three times.
            type = "conditional";
            # Card conditions take state, numeric_state, screen, user, and, or
            # but not template, so this is an explicit or over the three.
            conditions = [
              {
                condition = "or";
                conditions = map (room: {
                  condition = "state";
                  entity = shedTimer room;
                  state = "active";
                }) roomNames;
              }
            ];
            card = {
              type = "entities";
              title = "Paused to free up capacity";
              entities = map (room: {
                entity = shedTimer room;
                name = "${rooms.${room}} paused";
              }) roomNames;
            };
          }
        ];
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
              min = 64;
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
    # hvac_system_mode is the seasonal baseline. hvac_override_mode is chosen
    # before Apply and cleared when the override expires, so a temporary
    # change of mode cannot outlive the temperatures it came with. The fan
    # selects default to following the schedule.
    input_select = {
      hvac_system_mode = {
        name = "Normal mode";
        options = [
          "cool"
          "heat"
          "off"
        ];
        initial = "cool";
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
        initial = followSystem;
        icon = "mdi:hvac";
      };
    }
    // (lib.listToAttrs (
      lib.concatMap (room: [
        {
          name = "hvac_fan_${room}";
          value = {
            name = "${rooms.${room}} fan";
            options = fanOptions;
            initial = fanFollowsSchedule;
            icon = "mdi:fan";
          };
        }
        {
          name = "hvac_airflow_${room}";
          value = {
            name = "${rooms.${room}} airflow";
            options = airflowOptions;
            initial = airflowFollowsSchedule;
            icon = "mdi:weather-windy";
          };
        }
      ]) roomNames
    ));

    # No initial: it forces the value at every start, so a deploy silently
    # re-enabled rooms that had been deselected. Without it these restore
    # their last state, which is what deselecting a room has to mean. They
    # are all on today, so nothing is stranded off by the change.
    input_boolean = lib.listToAttrs (
      map (room: {
        name = "hvac_enable_${room}";
        value = {
          name = "${rooms.${room}} enabled";
          icon = "mdi:air-conditioner";
        };
      }) roomNames
    );

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
      hvac_apply_override = {
        alias = "Apply temperature override";
        icon = "mdi:tune-variant";
        sequence = [
          {
            action = "timer.start";
            target.entity_id = map overrideTimer roomNames;
            data.duration = "{{ states('input_number.hvac_override_minutes') | int(60) * 60 }}";
          }
        ];
      };

      # Drops every override at once. Nudging a thermostat card directly needs
      # no undo: the controller reasserts its own setpoint within the minute.
      hvac_back_to_schedule = {
        alias = "Back to schedule";
        icon = "mdi:calendar-clock";
        sequence = [
          {
            action = "timer.cancel";
            target.entity_id = map overrideTimer roomNames;
          }
        ];
      };

      # A nap is the override mechanism pointed at one room: sleeping
      # temperature, top priority, for as long as asked. The duration is a
      # field rather than only the slider so an Android widget can carry its
      # own value without opening the app.
      hvac_start_nap = {
        alias = "Start nap";
        icon = "mdi:power-sleep";
        fields.minutes = {
          name = "Minutes";
          description = "Nap length; defaults to the dashboard slider.";
          example = 45;
          selector.number = {
            min = 20;
            max = 240;
            step = 10;
          };
        };
        sequence = [
          {
            action = "input_number.set_value";
            target.entity_id = overrideNumber "bedroom";
            data.value = sleeping.bedroom.coolAbove;
          }
          {
            action = "timer.start";
            target.entity_id = overrideTimer "bedroom";
            data.duration = ''
              {{ (minutes | default(states('input_number.hvac_nap_minutes'), true) | int(60)) * 60 }}'';
          }
        ];
      };

      hvac_end_nap = {
        alias = "End nap";
        icon = "mdi:power-sleep";
        sequence = [
          {
            action = "timer.cancel";
            target.entity_id = overrideTimer "bedroom";
          }
        ];
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
