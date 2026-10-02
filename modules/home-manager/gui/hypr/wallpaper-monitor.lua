-- Restart only the wallpaper attached to an output whose actual mode changed.
-- Waiting for two matching samples lets the compositor finish its modeset.
return function(commands)
    if wallpaperMonitorTimer then
        wallpaperMonitorTimer:set_enabled(false)
    end

    local pending, refreshed = {}, {}
    wallpaperMonitorTimer = hl.timer(function()
        for name, command in pairs(commands) do
            local monitor = hl.get_monitor(name)
            if not monitor then
                -- The same mode after a reconnect still needs a new surface.
                pending[name], refreshed[name] = nil, nil
            elseif monitor.dpms_status then
                local signature = table.concat({
                    monitor.width, monitor.height,
                    monitor.refresh_rate, monitor.scale, monitor.transform,
                    monitor.cm,
                }, ":")
                if pending[name] ~= signature then
                    pending[name] = signature
                elseif refreshed[name] ~= signature then
                    -- Asynchronous and non-blocking; deliberately stopped
                    -- wallpaper services stay stopped (systemctl try-restart).
                    hl.exec_cmd(command)
                    refreshed[name] = signature
                end
            end
        end
    end, { timeout = 1000, type = "repeat" })
end
