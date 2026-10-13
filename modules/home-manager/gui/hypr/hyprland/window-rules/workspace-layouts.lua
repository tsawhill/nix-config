-- Layout boxes are monitor-global logical coordinates inside the work area
-- (outer gaps already removed). Hyprland applies inner gaps and pseudotile
-- content size inside these boxes.
local function rows(targets, area)
    for i, target in ipairs(targets) do
        local top = math.floor((i - 1) * area.h / #targets)
        local bottom = math.floor(i * area.h / #targets)
        target:place({ x = area.x, y = area.y + top, w = area.w, h = bottom - top })
    end
end

local function isStream(window)
    return window ~= nil and window.class == "com.moonlight_stream.Moonlight"
        and window.title:match(" %- Moonlight$") ~= nil
end

local M = {}

function M.steam()
    hl.layout.register("steam-dashboard", {
        recalculate = function(ctx)
            local library, friends, chats = {}, {}, {}
            for _, target in ipairs(ctx.targets) do
                local w = target.window
                if w and w.class:lower() == "steam" and w.title == "Steam" then
                    table.insert(library, target)
                elseif w and w.class:lower() == "steam" and w.title == "Friends List" then
                    table.insert(friends, target)
                else
                    table.insert(chats, target)
                end
            end
            local a = ctx.area
            local left = (#library > 0 and (#friends + #chats > 0)) and math.floor(a.w * 0.60)
                or (#library > 0 and a.w or 0)
            rows(library, { x = a.x, y = a.y, w = left, h = a.h })
            local top = (#chats > 0 and #friends > 0) and math.floor(a.h * 0.52)
                or (#chats > 0 and a.h or 0)
            rows(chats, { x = a.x + left, y = a.y, w = a.w - left, h = top })
            rows(friends, { x = a.x + left, y = a.y + top, w = a.w - left, h = a.h - top })
        end,
    })
    hl.workspace_rule({ workspace = "4", layout = "lua:steam-dashboard" })
end

function M.secondary(streamWidth)
    hl.layout.register("secondary-apps", {
        recalculate = function(ctx)
            local streams, others = {}, {}
            for _, target in ipairs(ctx.targets) do
                table.insert(isStream(target.window) and streams or others, target)
            end
            local a = ctx.area
            local width = 0
            if #streams > 0 then
                -- The stream hugs the left edge, so only its right side gets an inner gap.
                local gaps = hl.get_config("general.gaps_in")
                width = math.min(a.w, streamWidth + (type(gaps) == "table" and gaps.right or gaps or 0))
                -- On a narrow monitor, let pseudotiling shrink the stream so chat stays usable.
                if #others > 0 then width = math.min(width, math.floor(a.w * 0.75)) end
            end
            rows(streams, { x = a.x, y = a.y, w = width, h = a.h })
            rows(others, { x = a.x + width, y = a.y, w = a.w - width, h = a.h })
        end,
    })
    hl.workspace_rule({ workspace = "6", layout = "lua:secondary-apps" })
end

return M
