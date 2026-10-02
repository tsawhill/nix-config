-- AW3423DWF changes its advertised modes when its hardware PbP split changes.
-- Match the display identity, not its connector (HDMI on the cube, DP elsewhere).
do
    local output = "desc:Dell Inc. AW3423DWF 3D442S3"
    local function rule(mode, hdr)
        return {
            output = output,
            mode = mode,
            position = "auto-right",
            scale = 1,
            bitdepth = hdr and 10 or 8,
            supports_hdr = hdr and 1 or -1,
            supports_wide_color = hdr and 1 or -1,
            cm = hdr and "hdr" or "srgb",
            sdr_min_luminance = 0.005,
            sdr_max_luminance = 240,
            min_luminance = 0,
            max_luminance = 400,
            max_avg_luminance = 300,
            vrr = 0,
        }
    end

    -- Start safely even when logging in with PbP already enabled. Never request
    -- an unsupported full-width mode while waiting for the output to appear.
    hl.monitor(rule("preferred", false))

    local pending, applied
    local function update()
        local monitor = hl.get_monitor(output)
        if not monitor then
            pending, applied = nil, nil
            return
        end

        -- Exactly one of these native widths should be advertised. Ignore
        -- unknown/ambiguous lists during transitions rather than guessing HDR.
        local native = { [3440] = true, [2304] = true, [1720] = true, [1136] = true }
        local best, width
        for _, mode in ipairs(monitor.available_modes or {}) do
            if mode.height == 1440 and native[mode.width] then
                if width and width ~= mode.width then
                    pending = nil
                    return
                end
                width = mode.width
                if not best or mode.refresh_rate > best.refresh_rate then
                    best = mode
                end
            end
        end
        if not best then
            pending = nil
            return
        end

        local mode = string.format("%dx%d@%.3fHz", best.width, best.height, best.refresh_rate)
        local signature = monitor.name .. ":" .. mode
        if pending ~= signature then
            pending = signature
            return
        end
        if applied == signature then
            return
        end

        hl.monitor(rule(mode, best.width == 3440))
        applied = signature
    end

    -- Mode-list changes need not remove/re-add the output. Check in-process,
    -- without spawning hyprctl, and wait for two consecutive matching samples.
    -- Replace the timer if this chunk is sourced again in the same Lua context.
    if aw3423dwfProfileTimer then
        aw3423dwfProfileTimer:set_enabled(false)
    end
    aw3423dwfProfileTimer = hl.timer(update, { timeout = 1000, type = "repeat" })
end
