{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Web UIs launched as standalone windows, each with its own browser profile.
  apps = {
    qui = {
      name = "qBittorrent";
      comment = "qui for qbit-gen and qbit-lts";
      url = "https://qbit.tsawhill.org";
      icon = "qbittorrent";
    };
  };

  mkEntry = id: app: {
    inherit (app) name comment icon;
    exec = lib.concatStringsSep " " [
      "${pkgs.ungoogled-chromium}/bin/chromium"
      "--app=${app.url}"
      "--user-data-dir=${config.xdg.dataHome}/web-apps/${id}"
      "--class=web-app-${id}"
      "--ozone-platform-hint=auto"
    ];
    type = "Application";
    terminal = false;
    categories = [ "Network" ];
    settings.StartupWMClass = "web-app-${id}";
  };
in
{
  xdg.desktopEntries = lib.mapAttrs' (
    id: app: lib.nameValuePair "web-app-${id}" (mkEntry id app)
  ) apps;
}
