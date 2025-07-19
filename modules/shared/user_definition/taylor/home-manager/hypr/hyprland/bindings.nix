{

  ################################
  #                              #
  #         Key bindings         #
  #                              #
  ################################
  wayland.windowManager.hyprland.settings.bind = [
    "$mainMod, B, exec, floorp"
    "$mainMod, Return, exec, foot"
    "$mainMod_SHIFT, Q, killactive, "
    "$mainMod_SHIFT, E, exit, "
    "$mainMod_CTRL, Z, exec, pactl set-source-mute 0 toggle"
    "$mainMod, Next, exec, pkill -USR1 'gpu-screen-re*' && sleep 0.5 && notify-send -t 1500 -u low -- \"GPU Screen Recorder\" \"Replay saved\""
    "$mainMod, Delete, exec, grimblast copysave area; pkill -9 hyprpanel; hyprpanel"
    "$mainMod, Page_Up, exec, grimblast copysave active; pkill -9 hyprpanel; hyprpanel"
    ", Print, exec, grimblast copysave output; pkill -9 hyprpanel; hyprpanel"
    "$mainMod, F, fullscreen"
    "$mainMod, E, exec, nemo"
    "$mainMod, Space, togglefloating, "
    "$mainMod, D, exec, MANGOHUD=0 walker"
    "$mainMod, P, pseudo, "
    "$mainMod, V, togglesplit, "

    # Switch workspaces with mainMod + [0-9]
    "$mainMod, 1, workspace, 1"
    "$mainMod, 2, workspace, 2"
    "$mainMod, 3, workspace, 3"
    "$mainMod, 4, workspace, 4"
    "$mainMod, 5, workspace, 5"
    "$mainMod, 6, workspace, 6"
    "$mainMod, 7, workspace, 7"
    "$mainMod, 8, workspace, 8"
    "$mainMod, 9, workspace, 9"
    "$mainMod, 0, workspace, 10"

    # Move active window to a workspace with mainMod + SHIFT + [0-9]
    "$mainMod SHIFT, 1, movetoworkspace, 1"
    "$mainMod SHIFT, 2, movetoworkspace, 2"
    "$mainMod SHIFT, 3, movetoworkspace, 3"
    "$mainMod SHIFT, 4, movetoworkspace, 4"
    "$mainMod SHIFT, 5, movetoworkspace, 5"
    "$mainMod SHIFT, 6, movetoworkspace, 6"
    # "$mainMod SHIFT, 7, movetoworkspace, 7"
    "$mainMod SHIFT, 8, movetoworkspace, 8"
    "$mainMod SHIFT, 9, movetoworkspace, 9"
    "$mainMod SHIFT, 0, movetoworkspace, 10"
    "$mainMod SHIFT, 7, movetoworkspace, 11"

    # Scroll through existing workspaces with mainMod + scroll
    "$mainMod, mouse_down, workspace, e+1"
    "$mainMod, mouse_up, workspace, e-1"

    # Move focus with mainMod + arrow keys
    "$mainMod, left, movefocus, l"
    "$mainMod, right, movefocus, r"
    "$mainMod, up, movefocus, u"
    "$mainMod, down, movefocus, d"
  ];

  ################################
  #                              #
  #    Repeated key bindings     #
  #                              #
  ################################
  wayland.windowManager.hyprland.settings.binde = [
    "$mainMod SHIFT, right, resizeactive, 30 0"
    "$mainMod SHIFT, left, resizeactive, -30 0"
    "$mainMod SHIFT, up, resizeactive, 0 -30"
    "$mainMod SHIFT, down, resizeactive, 0 30"
  ];

  ################################
  #                              #
  #        Mouse bindings        #
  #                              #
  ################################
  wayland.windowManager.hyprland.settings.bindm = [
    # Move/resize windows with mainMod + LMB/RMB and dragging
    "$mainMod, mouse:272, movewindow"
    "$mainMod, mouse:273, resizeactive"
  ];
}
