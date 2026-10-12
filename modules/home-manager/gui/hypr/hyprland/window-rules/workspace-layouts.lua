-- Layout boxes are monitor-global logical coordinates. Hyprland applies the
-- workspace gaps, borders and pseudotile content size inside these boxes.
local function rows(targets, area)
    for i, target in ipairs(targets) do
        local top = math.floor((i - 1) * area.h / #targets)
        local bottom = math.floor(i * area.h / #targets)
        target:place({ x = area.x, y = area.y + top, w = area.w, h = bottom - top })
    end
end

local function isRunelite(window)
    return window and window.class == "com.moonlight_stream.Moonlight"
        and window.title:lower():match("runelite.* %- moonlight$") ~= nil
end

return function(steamEnabled, secondaryEnabled)
    if steamEnabled then
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

    if secondaryEnabled then
        hl.layout.register("secondary-apps", {
            recalculate = function(ctx)
                local streams, others = {}, {}
                for _, target in ipairs(ctx.targets) do
                    table.insert(isRunelite(target.window) and streams or others, target)
                end
                local a = ctx.area
                local border = hl.get_config("general.border_size")
                local inner = hl.get_config("general.gaps_in")
                local outer = hl.get_config("general.gaps_out")
                -- Reserve the stream's 1180 logical pixels plus the decorations
                -- removed from its cell. Vesktop gets the entire remaining cell.
                local width = math.min(a.w, 1180 + 2 * border + outer.left + inner.right)
                if #streams == 0 then width = 0 end
                -- If a smaller display cannot fit the fixed stream plus a
                -- useful chat column, let pseudotiling shrink to fit its cell.
                if #others > 0 then width = math.min(width, math.floor(a.w * 0.75)) end
                rows(streams, { x = a.x, y = a.y, w = width, h = a.h })
                rows(others, { x = a.x + width, y = a.y, w = a.w - width, h = a.h })
            end,
        })
        hl.workspace_rule({ workspace = "6", layout = "lua:secondary-apps" })
    end
end
