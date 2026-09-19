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

  block = from: blockRooms: {
    inherit from;
    fromMinutes = minutesOf from;
    rooms = blockRooms;
  };

  # heatBelow only applies when the system mode is set to heat. The house does
  # not drop below 68 in practice, so these are placeholders to be revisited
  # before winter rather than numbers anyone has lived with.

  # Asleep: only the bedroom matters, the rest just must not bake.
  sleeping = {
    bedroom = { coolAbove = 72; heatBelow = 66; priority = 10; };
    office = { coolAbove = 82; heatBelow = 60; priority = 1; };
    living_room = { coolAbove = 82; heatBelow = 60; priority = 1; };
  };

  # Working. Taylor is in the office every day, weekends included.
  working = {
    office = { coolAbove = 75; heatBelow = 68; priority = 10; };
    living_room = { coolAbove = 78; heatBelow = 66; priority = 5; };
    bedroom = { coolAbove = 80; heatBelow = 60; priority = 1; };
  };

  # The bedroom pulls down while the office is still occupied, so it is at
  # temperature on arrival rather than starting from 80.
  preBed = {
    bedroom = { coolAbove = 72; heatBelow = 66; priority = 10; };
    office = { coolAbove = 75; heatBelow = 68; priority = 5; };
    living_room = { coolAbove = 80; heatBelow = 60; priority = 1; };
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
        (block "00:00" sleeping)
        (block "06:00" working)
        (block "22:00" preBed)
      ];
      # No work the next morning, so bed is later.
      fridayNight = [
        (block "00:00" sleeping)
        (block "06:00" working)
        (block "23:30" preBed)
      ];
      weekendLate = [
        (block "00:00" sleeping)
        (block "09:30" working)
        (block "23:30" preBed)
      ];
      # Sunday night returns to the work-week bedtime.
      weekend = [
        (block "00:00" sleeping)
        (block "09:30" working)
        (block "22:00" preBed)
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
  # single system-wide choice rather than a per-room one.
  systemMode = "input_select.hvac_system_mode";
  enableToggle = room: "input_boolean.hvac_enable_${room}";

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

  # Resolve what the room should be doing into one value, so the automation
  # below is "apply this" rather than a tree of cool and heat branches. Holding
  # the current mode inside the hysteresis band is what stops a room chattering
  # on and off around a single number.
  desiredTemplate = room: ''
    {%- set sys = states('${systemMode}') -%}
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
    {%- set sys = states('${systemMode}') -%}
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
      { trigger = "state"; entity_id = systemMode; }
      { trigger = "state"; entity_id = enableToggle room; }
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
          # Idle and staying idle: keep the dial showing the setpoint this room
          # would use. With the head off, SmartIR stores the value without
          # transmitting, so this costs no IR and stops a never-commanded room
          # displaying its minimum temperature.
          {
            conditions = [
              {
                condition = "template";
                value_template = ''
                  {{ desired == 'off' and current_mode == 'off'
                     and (state_attr('${climateEntity room}', 'temperature') | float(0)) != setpoint }}'';
              }
            ];
            sequence = [
              {
                action = "climate.set_temperature";
                target.entity_id = climateEntity room;
                data.temperature = "{{ setpoint }}";
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
          trigger = "homeassistant";
          event = "start";
        }
      ];
    actions = map (room: {
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
              data.value = "{{ states('${targetSensor room}') | float(75) | round(0) }}";
            }
          ];
        }
      ];
    }) roomNames;
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
    actions = map (room: {
      choose = [
        {
          conditions = [
            {
              condition = "template";
              value_template = "{{ is_state('${climateEntity room}', 'cool') }}";
            }
          ];
          sequence = [
            {
              action = "climate.set_temperature";
              target.entity_id = climateEntity room;
              data = {
                hvac_mode = "cool";
                temperature = "{{ state_attr('${climateEntity room}', 'temperature') | round(0) }}";
              };
            }
          ];
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
            cards = map (room: {
              type = "thermostat";
              entity = climateEntity room;
              name = rooms.${room};
            }) roomNames;
          }
          {
            # The thermostat dials already show each room's temperature, so this
            # only has to answer "why is it doing that": the threshold in force
            # right now, whether from the schedule or an override.
            type = "glance";
            title = "Cool above";
            columns = 3;
            entities = map (room: {
              entity = targetSensor room;
              name = rooms.${room};
            }) roomNames;
          }
          {
            type = "entities";
            title = "Override";
            # The header toggle would flip every switch on this card at once,
            # which is never what anyone means here.
            show_header_toggle = false;
            # Mode first because it applies to everything: the heads share an
            # outdoor unit and cannot run opposing modes. Then the per-room
            # switches, then temperatures, a duration, and Apply. Expiry hands
            # control back to the schedule on its own.
            entities = [
              {
                entity = systemMode;
                name = "Mode (all rooms)";
              }
              { type = "divider"; }
            ]
            ++ (map (room: {
              entity = enableToggle room;
              name = "${rooms.${room}} on";
            }) roomNames)
            ++ [ { type = "divider"; } ]
            ++ (map (room: {
              entity = overrideNumber room;
              name = rooms.${room};
            }) roomNames)
            ++ [
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
            type = "vertical-stack";
            cards = [
              {
                type = "entities";
                title = "Paused to free up capacity";
                entities = map (room: {
                  entity = shedTimer room;
                  name = "${rooms.${room}} paused";
                }) roomNames;
              }
              {
                # This card exists because "capacity shedding" means nothing
                # until you have watched it happen on a hot afternoon.
                type = "markdown";
                content = ''
                  On a hot day all three heads pull from one outdoor unit and
                  none of them quite wins. When the room that matters most
                  stops getting cooler, the least important room running is
                  paused for a while so the capacity goes where you want it.
                  **Idle** means this is not happening.
                '';
              }
            ];
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
    input_select.hvac_system_mode = {
      name = "System mode";
      options = [
        "cool"
        "heat"
        "off"
      ];
      initial = "cool";
      icon = "mdi:hvac";
    };

    # initial, because Home Assistant creates an input_boolean in the off
    # state rather than an unknown one, which would leave every room excluded
    # until someone noticed. A restart therefore re-enables all three: a
    # temporary exclusion should not outlive a restart silently.
    input_boolean = lib.listToAttrs (
      map (room: {
        name = "hvac_enable_${room}";
        value = {
          name = "${rooms.${room}} enabled";
          icon = "mdi:air-conditioner";
          initial = true;
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
