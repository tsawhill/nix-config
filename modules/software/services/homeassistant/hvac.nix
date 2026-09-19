{ lib, ... }:

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
    # How far under the threshold the head is told to aim. Its own sensor reads
    # ceiling air and runs warm, so this keeps it from satisfying itself early.
    setpointOffset = 4;
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
    (lib.toInt (builtins.elemAt parts 0)) * 60 + (lib.toInt (builtins.elemAt parts 1));

  block = from: blockRooms: {
    inherit from;
    fromMinutes = minutesOf from;
    rooms = blockRooms;
  };

  # Asleep: only the bedroom matters, the rest just must not bake.
  sleeping = {
    bedroom = { coolAbove = 72; priority = 10; };
    office = { coolAbove = 82; priority = 1; };
    living_room = { coolAbove = 82; priority = 1; };
  };

  # Working. Taylor is in the office every day, weekends included.
  working = {
    office = { coolAbove = 75; priority = 10; };
    living_room = { coolAbove = 78; priority = 5; };
    bedroom = { coolAbove = 80; priority = 1; };
  };

  # The bedroom pulls down while the office is still occupied, so it is at
  # temperature on arrival rather than starting from 80.
  preBed = {
    bedroom = { coolAbove = 72; priority = 10; };
    office = { coolAbove = 75; priority = 5; };
    living_room = { coolAbove = 80; priority = 1; };
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
  targetSensor = room: "sensor.hvac_target_${room}";
  prioritySensor = room: "sensor.hvac_priority_${room}";

  # Resolve today's pattern and the block covering the current minute.
  currentBlock = ''
    {% set schedule = ${scheduleJson} %}
    {% set blocks = schedule.patterns[schedule.days[now().strftime('%A') | lower]] %}
    {% set mins = now().hour * 60 + now().minute %}
    {% set ns = namespace(current = blocks[0]) %}
    {% for b in blocks %}
      {% if mins >= b.fromMinutes %}{% set ns.current = b %}{% endif %}
    {% endfor %}
  '';

  # An active override replaces the scheduled value for as long as it runs.
  targetTemplate = room: ''
    ${currentBlock}
    {% if is_state('${overrideTimer room}', 'active') %}
      {{ states('${overrideNumber room}') | round(0) }}
    {% else %}
      {{ ns.current.rooms['${room}'].coolAbove }}
    {% endif %}
  '';

  priorityTemplate = room: ''
    ${currentBlock}
    {% if is_state('${overrideTimer room}', 'active') %}
      ${toString tuning.overridePriority}
    {% else %}
      {{ ns.current.rooms['${room}'].priority }}
    {% endif %}
  '';

  roomVariables = room: {
    room_temp = "{{ states('${tempSensor room}') | float(-999) }}";
    target = "{{ states('${targetSensor room}') | float(999) }}";
    shed = "{{ is_state('${shedTimer room}', 'active') }}";
    current_mode = "{{ states('${climateEntity room}') }}";
    stale = ''
      {% set s = states.sensor.ac_controller_${room}_temperature %}
      {{ s is none
         or s.state in ['unknown', 'unavailable']
         or (now() - s.last_updated).total_seconds() > ${toString (tuning.staleMinutes * 60)} }}'';
    held = ''
      {% set c = states.climate.${room}_ac %}
      {{ 0 if c is none else (now() - c.last_changed).total_seconds() }}'';
    setpoint = ''
      {% set t = states('${targetSensor room}') | float(999) %}
      {{ [[t - ${toString tuning.setpointOffset}, 64] | max, 86] | min | round(0) }}'';
  };

  offAction = room: {
    action = "climate.set_hvac_mode";
    target.entity_id = climateEntity room;
    data.hvac_mode = "off";
  };

  mkRoomAutomation = room: {
    alias = "HVAC ${rooms.${room}}";
    description = "Threshold cooling for ${rooms.${room}}, with shedding and a stale-sensor stop.";
    mode = "single";
    triggers = [
      { trigger = "state"; entity_id = tempSensor room; }
      { trigger = "state"; entity_id = targetSensor room; }
      { trigger = "state"; entity_id = shedTimer room; }
      { trigger = "time_pattern"; minutes = "/1"; }
    ];
    actions = [
      { variables = roomVariables room; }
      {
        choose = [
          # Nothing trustworthy to act on, so stop rather than run blind.
          {
            conditions = [
              {
                condition = "template";
                value_template = "{{ (stale or room_temp < -900) and current_mode != 'off' }}";
              }
            ];
            sequence = [ (offAction room) ];
          }
          # Shed by the capacity guard, or satisfied. Either way stop, once the
          # compressor has run long enough to be worth having started.
          {
            conditions = [
              {
                condition = "template";
                value_template = ''
                  {{ (shed or room_temp <= target - ${toString tuning.hysteresis})
                     and current_mode != 'off'
                     and held > ${toString (tuning.minRunMinutes * 60)} }}'';
              }
            ];
            sequence = [ (offAction room) ];
          }
          # Too warm. Start cooling, or correct a setpoint that has drifted.
          {
            conditions = [
              {
                condition = "template";
                value_template = ''
                  {{ not shed and not stale and room_temp > target
                     and (current_mode != 'cool'
                          or (state_attr('${climateEntity room}', 'temperature') | float(0)) != setpoint)
                     and (current_mode == 'cool' or held > ${toString (tuning.minOffMinutes * 60)}) }}'';
              }
            ];
            sequence = [
              {
                action = "climate.set_temperature";
                target.entity_id = climateEntity room;
                data = {
                  hvac_mode = "cool";
                  temperature = "{{ setpoint }}";
                };
              }
            ];
          }
        ];
      }
    ];
  };

  # Record the temperature a room started at, so progress can be measured
  # without depending on a statistics or derivative integration.
  startTempAutomation = {
    alias = "HVAC record start temperature";
    description = "Snapshot room temperature whenever a head begins cooling.";
    mode = "queued";
    triggers = map (room: {
      trigger = "state";
      entity_id = climateEntity room;
      to = "cool";
      id = room;
    }) roomNames;
    actions = [
      {
        choose = map (room: {
          conditions = [
            {
              condition = "trigger";
              id = room;
            }
          ];
          sequence = [
            {
              action = "input_number.set_value";
              target.entity_id = startTempNumber room;
              data.value = "{{ states('${tempSensor room}') | float(0) | round(1) }}";
            }
          ];
        }) roomNames;
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
            {% set ns = namespace(pick = '', best = -1) %}
            ${lib.concatMapStrings (room: ''
              {% if ${stalledExpr room} and (states('${prioritySensor room}') | int(0)) > ns.best %}
                {% set ns.pick = '${room}' %}
                {% set ns.best = states('${prioritySensor room}') | int(0) %}
              {% endif %}
            '') roomNames}
            {{ ns.pick }}'';
          victim = ''
            {% set ns = namespace(pick = '', worst = 999) %}
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
in
{
  # input_number and timer arrive with default_config, and template has no
  # dependencies of its own, so none of this needs extraComponents.
  services.home-assistant.config = {
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
      ]) roomNames
    );

    template = [
      {
        sensor =
          (map (room: {
            name = "hvac_target_${room}";
            unique_id = "hvac_target_${room}";
            unit_of_measurement = "°F";
            state = targetTemplate room;
          }) roomNames)
          ++ (map (room: {
            name = "hvac_priority_${room}";
            unique_id = "hvac_priority_${room}";
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

      hvac_cancel_override = {
        alias = "Cancel temperature override";
        icon = "mdi:tune-variant";
        sequence = [
          {
            action = "timer.cancel";
            target.entity_id = map overrideTimer roomNames;
          }
        ];
      };

      # A nap is the override mechanism pointed at one room: sleeping
      # temperature, top priority, for as long as the slider says.
      hvac_start_nap = {
        alias = "Start nap";
        icon = "mdi:power-sleep";
        sequence = [
          {
            action = "input_number.set_value";
            target.entity_id = overrideNumber "bedroom";
            data.value = sleeping.bedroom.coolAbove;
          }
          {
            action = "timer.start";
            target.entity_id = overrideTimer "bedroom";
            data.duration = "{{ states('input_number.hvac_nap_minutes') | int(60) * 60 }}";
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
      startTempAutomation
      reconcileAutomation
      shedAutomation
    ];
  };
}
