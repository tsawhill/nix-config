{
  config,
  lib,
  pkgs,
  ...
}:
let
  wayle = config.services.wayle;
  # Match the other tray icons, which draw in the bar's background colour.
  color = wayle.settings.styling.palette.bg or "#242438";
  icons = {
    auto = "si-steam";
    away = "ld-moon";
    invisible = "ld-eye-off";
    off = "si-steam";
  };
  presence = pkgs.stdenv.mkDerivation {
    pname = "steam-presence";
    version = "1.0";
    src = ./steam-presence.py;
    dontUnpack = true;
    dontBuild = true;
    nativeBuildInputs = [
      pkgs.wrapGAppsHook3
      pkgs.gobject-introspection
      pkgs.librsvg
    ];
    # python3 stays in buildInputs so patchShebangs picks the pygobject env.
    buildInputs = [
      (pkgs.python3.withPackages (ps: [ ps.pygobject3 ]))
      pkgs.gtk3
      pkgs.libayatana-appindicator
    ];
    installPhase = ''
      runHook preInstall
      install -Dm755 $src $out/bin/steam-presence
      mkdir -p $out/share/steam-presence/icons
      ${lib.concatStrings (
        lib.mapAttrsToList (mode: icon: ''
          sed "s/rgb(0,0,0)/${color}/g" ${wayle.package}/share/icons/hicolor/scalable/actions/${icon}-symbolic.svg > ${mode}.svg
          rsvg-convert --width 64 --height 64 ${mode}.svg --output $out/share/steam-presence/icons/${mode}.png
        '') icons
      )}
      runHook postInstall
    '';
    preFixup = ''
      gappsWrapperArgs+=(--prefix PATH : ${
        lib.makeBinPath [
          pkgs.procps
          pkgs.systemd
        ]
      })
    '';
  };
  command = "${presence}/bin/steam-presence";
  session = "wayland-session@hyprland.desktop.target";
  # The NixOS steam launcher lives on the system profile.
  path = "PATH=/run/current-system/sw/bin:%h/.nix-profile/bin";
in
{
  home.packages = [ presence ];
  # The steam-presence tray icon replaces Steam's own.
  services.wayle.settings.modules.systray.blacklist = [ "steam" ];
  services.hypridle.settings.listener = lib.mkAfter [
    {
      timeout = 300;
      ignore_inhibit = true;
      on-timeout = "${command} idle";
      on-resume = "${command} resume";
    }
  ];
  systemd.user.services.steam-presence-tray = {
    Unit = {
      Description = "Steam presence tray icon";
      After = [ session ];
      PartOf = [ session ];
    };
    Service = {
      ExecStart = "${command} tray";
      Environment = path;
      Restart = "on-failure";
      RestartSec = "5s";
    };
    Install.WantedBy = [ session ];
  };
  systemd.user.services.steam-presence = {
    Unit = {
      Description = "Apply selected Steam presence mode";
      After = [ session ];
      PartOf = [ session ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${command} tick";
      Environment = path;
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
      OnUnitActiveSec = "5min";
    };
    Install.WantedBy = [ session ];
  };
}
