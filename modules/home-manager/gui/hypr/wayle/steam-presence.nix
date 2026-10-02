{
  config,
  lib,
  pkgs,
  ...
}:
let
  menu = if config.services.walker.enable then pkgs.walker else pkgs.fuzzel;
  script = pkgs.writeText "steam-presence.py" (
    builtins.replaceStrings
      [ "@menu@" ]
      [ "${menu}/bin/${if config.services.walker.enable then "walker" else "fuzzel"}" ]
      (builtins.readFile ./steam-presence.py)
  );
  presence = pkgs.writeShellApplication {
    name = "steam-presence";
    runtimeInputs = [
      pkgs.python3
      pkgs.procps
      pkgs.systemd
    ];
    text = ''exec python3 ${script} "$@"'';
  };
  command = "${presence}/bin/steam-presence";
  session = "wayland-session@hyprland.desktop.target";
in
{
  home.packages = [ presence ];
  services.wayle.settings.modules.custom = [
    {
      id = "steam-presence";
      command = "${command} status";
      interval-ms = 5000;
      hide-if-empty = true;
      icon-name = "si-steam-symbolic";
      icon-map = {
        auto = "si-steam-symbolic";
        away = "ld-moon-symbolic";
        invisible = "ld-eye-off-symbolic";
        off = "ld-gamepad-2-symbolic";
      };
      label-show = false;
      left-click = "${command} menu";
      right-click = "${command} menu";
    }
  ];
  # This button replaces Steam's own tray icon and menu.
  services.wayle.settings.modules.systray.blacklist = [
    "*steam*"
    "*Steam*"
  ];
  services.hypridle.settings.listener = lib.mkAfter [
    {
      timeout = 300;
      ignore_inhibit = true;
      on-timeout = "${command} idle";
      on-resume = "${command} resume";
    }
  ];
  systemd.user.services.steam-presence = {
    Unit = {
      Description = "Apply selected Steam presence mode";
      After = [ session ];
      PartOf = [ session ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${command} tick";
      Environment = "PATH=/run/current-system/sw/bin:%h/.nix-profile/bin";
    };
  };
  systemd.user.timers.steam-presence = {
    Unit = {
      Description = "Refresh Steam presence while active";
      PartOf = [ session ];
      After = [ session ];
    };
    Timer = {
      OnActiveSec = "15s";
      OnUnitActiveSec = "60s";
    };
    Install.WantedBy = [ session ];
  };
}
