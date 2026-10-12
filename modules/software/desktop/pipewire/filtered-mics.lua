-- Load a filtered mic's chain (its output is mic_input) only while its source node exists.
local rules = Conf.get_section_as_json ("filtered-mics.rules", Json.Array {})
-- Every chain is mic_input, so only one runs at a time.
local active = nil

SimpleEventHook {
  name = "node/filtered-mics/load",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "node-added" },
      Constraint { "media.class", "=", "Audio/Source" },
    },
  },
  execute = function (event)
    if active then
      return
    end
    local node = event:get_subject ()
    JsonUtils.match_rules (rules, node.properties, function (action, value)
      if action == "load-filter-chain" and not active then
        active = {
          id = node.id,
          capture = value:parse ()["capture.props"]["node.name"],
          module = LocalModule ("libpipewire-module-filter-chain", value:to_string (), {}),
        }
      end
    end)
  end,
}:register ()

SimpleEventHook {
  name = "node/filtered-mics/unload",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "node-removed" },
    },
  },
  execute = function (event)
    local node = event:get_subject ()
    if not active or active.id ~= node.id then
      return
    end
    local capture = active.capture
    active = nil
    -- The sandbox can't force a collection; filter-chain unloads itself once its capture is gone.
    local om = event:get_source ():call ("get-object-manager", "node")
    local stream = om:lookup { Constraint { "node.name", "=", capture, type = "pw" } }
    if stream then
      stream:request_destroy ()
    end
  end,
}:register ()
