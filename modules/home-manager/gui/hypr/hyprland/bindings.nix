{
  ################################
  #                              #
  #         Key bindings         #
  #                              #
  ################################
  # Hand-written Lua: hl.bind(keys, dispatcher_closure, opts?). `mainMod` is the
  # `local mainMod = "SUPER"` declared in default.nix (settings.mainMod._var).
  # Dispatchers are hl.dsp.* closures — NOT strings.
  wayland.windowManager.hyprland.extraConfig = ''
    -- Apps / actions
    hl.bind(mainMod .. " + B",      hl.dsp.exec_cmd("zen"))
    hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd("foot"))
    hl.bind(mainMod .. " + Next",   hl.dsp.exec_cmd([[pkill -USR1 'gpu-screen-re*' && sleep 0.5 && notify-send -t 1500 -u low -- "GPU Screen Recorder" "Replay saved"]]))
    hl.bind(mainMod .. " + Delete",  hl.dsp.exec_cmd("grimblast copysave area"))
    hl.bind(mainMod .. " + Page_Up", hl.dsp.exec_cmd("grimblast copysave active"))
    hl.bind("Print",                 hl.dsp.exec_cmd("grimblast copysave output"))
    hl.bind(mainMod .. " + F",      hl.dsp.window.fullscreen({}))
    hl.bind(mainMod .. " + E",      hl.dsp.exec_cmd("nemo"))
    hl.bind(mainMod .. " + Space",  hl.dsp.window.float({ action = "toggle" }))
    hl.bind(mainMod .. " + D",      hl.dsp.exec_cmd("walker"))
    hl.bind(mainMod .. " + R",      hl.dsp.exec_cmd("walker -m runner"))
    hl.bind(mainMod .. " + P",      hl.dsp.window.pseudo({}))
    hl.bind(mainMod .. " + V",      hl.dsp.layout("togglesplit"))
    hl.bind(mainMod .. " + W",      hl.dsp.layout("addmaster"))
    hl.bind(mainMod .. " + S",      hl.dsp.layout("removemaster"))

    -- Cycle through windows
    hl.bind(mainMod .. " + Tab",         hl.dsp.window.cycle_next({}))
    hl.bind(mainMod .. " + SHIFT + Tab", hl.dsp.window.cycle_next({ next = false }))

    -- Switch workspaces (mainMod + [0-9]) / move active window to workspace (mainMod + SHIFT + [0-9])
    for i = 1, 10 do
      local key = i % 10 -- 10 maps to key 0
      hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
      hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
    end

    -- Scroll through workspaces
    hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
    hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

    -- Move focus
    hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
    hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
    hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
    hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

    -- Move window
    hl.bind(mainMod .. " + CTRL + left",  hl.dsp.window.move({ direction = "left" }))
    hl.bind(mainMod .. " + CTRL + right", hl.dsp.window.move({ direction = "right" }))
    hl.bind(mainMod .. " + CTRL + up",    hl.dsp.window.move({ direction = "up" }))
    hl.bind(mainMod .. " + CTRL + down",  hl.dsp.window.move({ direction = "down" }))

    -- Mic mute
    hl.bind(mainMod .. " + CTRL + Z",      hl.dsp.exec_cmd("pactl set-source-mute @DEFAULT_SOURCE@ toggle"))
    hl.bind(mainMod .. " + XF86AudioMute", hl.dsp.exec_cmd("pactl set-source-mute @DEFAULT_SOURCE@ toggle"))

    -- Brightness
    hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl set +5%"))
    hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 5%-"))

    -- Repeated resize (binde)
    hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.resize({ x = 30,  y = 0 }),   { repeating = true })
    hl.bind(mainMod .. " + SHIFT + left",  hl.dsp.window.resize({ x = -30, y = 0 }),   { repeating = true })
    hl.bind(mainMod .. " + SHIFT + up",    hl.dsp.window.resize({ x = 0,   y = -30 }), { repeating = true })
    hl.bind(mainMod .. " + SHIFT + down",  hl.dsp.window.resize({ x = 0,   y = 30 }),  { repeating = true })

    -- Locked binds (bindl): fire even when a game has grabbed the keyboard
    hl.bind(mainMod .. " + SHIFT + Q", hl.dsp.window.close(), { locked = true })
    hl.bind(mainMod .. " + SHIFT + E", hl.dsp.exit(),         { locked = true })
    hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ +5%"),  { locked = true })
    hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ -5%"),  { locked = true })
    hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("pactl set-sink-mute @DEFAULT_SINK@ toggle"), { locked = true })

    -- Mouse binds (bindm): move/resize with mainMod + LMB/RMB drag
    hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
    hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
  '';
}
