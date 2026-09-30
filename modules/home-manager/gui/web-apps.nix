{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Icons missing from Tela come from selfh.st, the set Homepage uses, pinned to one commit.
  selfhst =
    name: sha256:
    toString (
      pkgs.fetchurl {
        url = "https://cdn.jsdelivr.net/gh/selfhst/icons@589d718a638b7770abae0edd1b60ff36c0dd1d5a/svg/${name}.svg";
        inherit sha256;
      }
    );

  # Web UIs launched as standalone windows, each with its own browser profile.
  apps = {
    homeassistant = {
      name = "Home Assistant";
      url = "https://ha.tsawhill.org";
      icon = selfhst "home-assistant" "146b366b8c09502742025c4bca4e029e8e4a1b277db837d59a23b93940ebe0e0";
    };
    jellyfin = {
      name = "Jellyfin";
      url = "https://jelly.tsawhill.org";
      icon = "jellyfin";
    };
    immich = {
      name = "Immich";
      url = "https://immich.tsawhill.org";
      icon = selfhst "immich" "a5d4a43899e63ffc7e97246034f7f63cdfdc410aa803c5713d545290601c4d89";
    };
    nextcloud = {
      name = "Nextcloud";
      url = "https://nc.tsawhill.org";
      icon = selfhst "nextcloud" "079b90f0f253f9d05e033b98b8b1093359f6cd7ff3e8b093d17a2dd34989d9d6";
    };
    seerr = {
      name = "Seerr";
      url = "https://request.tsawhill.org";
      icon = selfhst "seerr" "fc0db911f8201da22986c2de0f96d887b1be754d83f089aef0377745db23fbec";
    };
    qui = {
      name = "qBittorrent";
      url = "https://qbit.tsawhill.org";
      icon = "qbittorrent";
    };
    radarr = {
      name = "Radarr";
      url = "https://rad.tsawhill.org";
      icon = selfhst "radarr" "93aef4245d403c035a683baf9731eedb004637356b49f3b5c130b54d57e3490d";
    };
    sonarr = {
      name = "Sonarr";
      url = "https://son.tsawhill.org";
      icon = selfhst "sonarr" "9746c8d5858bb5a2153b0939bbe5de5d51eaca0e3fe827e418c245be53058dbb";
    };
    lidarr = {
      name = "Lidarr";
      url = "https://lid.tsawhill.org";
      icon = selfhst "lidarr" "5e38cd9ac3dec58d53efa2bba6ef14ac90002ebb5ad1e8d4f24bd18ab2db07d1";
    };
    prowlarr = {
      name = "Prowlarr";
      url = "https://pro.tsawhill.org";
      icon = selfhst "prowlarr" "1d485656651746e4f3d6421763b30e9cce873f212459d21fc36c0723386a0630";
    };
    open-webui = {
      name = "Open WebUI";
      url = "https://llm.tsawhill.org";
      icon = selfhst "open-webui" "e6c46823536661e25d9c382d77c53e8684151fc0bc42bd7a0784a9fedd2f9d46";
    };
  };

  mkEntry = id: app: {
    inherit (app) name icon;
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
