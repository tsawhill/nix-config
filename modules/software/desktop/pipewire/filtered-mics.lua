-- Run each filtered mic's chain only while its source node exists.
local rules = Conf.get_section_as_json ("filtered-mics.rules", Json.Array {})
-- Source node id -> { module, capture node name }.
local chains = {}

SimpleEventHook {
  name = "node/filtered-mics/load",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "node-added" },
      Constraint { "media.class", "=", "Audio/Source" },
    },
  },
  execute = function (event)
    local node = event:get_subject ()
    JsonUtils.match_rules (rules, node.properties, function (action, value)
      if action == "load-filter-chain" then
        chains[node.id] = {
          module = LocalModule ("libpipewire-module-filter-chain", value:to_string (), {}),
          capture = value:parse ()["capture.props"]["node.name"],
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
    local chain = chains[node.id]
    if not chain then
      return
    end
    chains[node.id] = nil
    -- The sandbox can't force a collection; filter-chain unloads itself once its capture is gone.
    local om = event:get_source ():call ("get-object-manager", "node")
    local capture = om:lookup { Constraint { "node.name", "=", chain.capture, type = "pw" } }
    if capture then
      capture:request_destroy ()
    end
  end,
}:register ()
