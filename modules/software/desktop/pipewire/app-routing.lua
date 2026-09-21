-- Route application playback centrally, including clients inside Proton containers.
local lutils = require("linking-utils")
local rules = Conf.get_section_as_json("app-routing.rules", Json.Array {})

SimpleEventHook {
  name = "linking/find-app-routing-target",
  before = { "linking/find-defined-target", "linking/prepare-link" },
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "select-target" },
    },
  },
  execute = function(event)
    local _, om, _, props, _, target = lutils:unwrap_select_target_event(event)
    -- Never route capture, hardware, or the output side of our virtual sinks.
    if target or props["media.class"] ~= "Stream/Output/Audio"
        or props["node.link-group"] ~= nil
        or props["node.virtual"] == "true" then
      return
    end

    -- Use a copy: session-item properties must not be mutated in place.
    local matched = {}
    for key, value in pairs(props) do matched[key] = value end
    matched["target.object"] = nil
    matched = JsonUtils.match_rules_update_properties(rules, matched)
    local name = matched["target.object"]
    if not name then return end

    for candidate in om:iterate { type = "SiLinkable" } do
      if candidate.properties["node.name"] == name
          and lutils.canLink(props, candidate) then
        event:set_data("target", candidate)
        return
      end
    end
    -- A disabled or unavailable sink leaves normal linking policy in control.
  end,
}:register()
