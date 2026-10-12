-- Load a filtered mic's chain (its output is mic_input) only while its source node exists.
local rules = Conf.get_section_as_json ("filtered-mics.rules", Json.Array {})
-- Every chain is mic_input, so only one runs at a time.
local active = nil

-- Unlike node-added hooks, this also reports nodes that existed before the script loaded.
-- Global on purpose: a local would be garbage collected, taking the chain module with it.
nodes_om = ObjectManager { Interest { type = "node" } }

nodes_om:connect ("object-added", function (_, node)
  if active or node.properties["media.class"] ~= "Audio/Source" then
    return
  end
  JsonUtils.match_rules (rules, node.properties, function (action, value)
    if action == "load-filter-chain" and not active then
      active = {
        id = node.id,
        capture = value:parse ()["capture.props"]["node.name"],
        module = LocalModule ("libpipewire-module-filter-chain", value:to_string (), {}),
      }
    end
  end)
end)

nodes_om:connect ("object-removed", function (om, node)
  if not active or active.id ~= node.id then
    return
  end
  local capture = active.capture
  active = nil
  -- The sandbox can't force a collection; filter-chain unloads itself once its capture is gone.
  local stream = om:lookup { Constraint { "node.name", "=", capture, type = "pw" } }
  if stream then
    stream:request_destroy ()
  end
end)

nodes_om:activate ()
