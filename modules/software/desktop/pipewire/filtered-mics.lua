-- Load a filtered mic's modules (the chain's output is mic_input) only while its source node exists.
local rules = Conf.get_section_as_json ("filtered-mics.rules", Json.Array {})
-- Rule actions in load order: echo cancellation works on the raw mic, the chain on its output.
local stages = {
  { action = "load-echo-cancel", module = "libpipewire-module-echo-cancel" },
  { action = "load-filter-chain", module = "libpipewire-module-filter-chain" },
}
-- Every chain is mic_input, so only one runs at a time.
local active = nil

-- Unlike node-added hooks, this also reports nodes that existed before the script loaded.
-- Global on purpose: a local would be garbage collected, taking the modules with it.
nodes_om = ObjectManager { Interest { type = "node" } }

nodes_om:connect ("object-added", function (_, node)
  if active or node.properties["media.class"] ~= "Audio/Source" then
    return
  end
  local actions = {}
  JsonUtils.match_rules (rules, node.properties, function (action, value)
    actions[action] = value
    -- Returning nothing would stop the walk after the first action.
    return true
  end)
  if not actions["load-filter-chain"] then
    return
  end
  active = { id = node.id, captures = {}, modules = {} }
  for _, stage in ipairs (stages) do
    local args = actions[stage.action]
    if args then
      table.insert (active.captures, args:parse ()["capture.props"]["node.name"])
      table.insert (active.modules, LocalModule (stage.module, args:to_string (), {}))
    end
  end
end)

nodes_om:connect ("object-removed", function (om, node)
  if not active or active.id ~= node.id then
    return
  end
  local captures = active.captures
  active = nil
  -- The sandbox can't force a collection; each module unloads itself once its capture is gone.
  for _, name in ipairs (captures) do
    local stream = om:lookup { Constraint { "node.name", "=", name, type = "pw" } }
    if stream then
      stream:request_destroy ()
    end
  end
end)

nodes_om:activate ()
