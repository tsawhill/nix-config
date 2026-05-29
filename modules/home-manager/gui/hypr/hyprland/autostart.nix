{ lib, pkgs, ... }:
{
  wayland.windowManager.hyprland.settings.exec-once = [
    # One-shot setup commands (not app launches)
    "rfkill unblock 0; sleep 15; rfkill unblock 0"

    # App launches (vesktop managed as systemd service below for portal ordering)
    "steam"
    "sleep 15; uwsm app -- heroic"
    "sleep 15; uwsm app -- feishin"
  ];

  # Persistent background processes managed as systemd user services
  systemd.user.services = {
    # programs.hyprpanel generates this service — only override the session target
    hyprpanel = {
      Unit = {
        After = lib.mkForce [ "wayland-session@hyprland.desktop.target" ];
        PartOf = lib.mkForce [ "wayland-session@hyprland.desktop.target" ];
      };
      Service.TimeoutStopSec = "5s";
      Install.WantedBy = lib.mkForce [ "wayland-session@hyprland.desktop.target" ];
    };

    hyprpolkitagent = {
      Unit = {
        Description = "Hyprland Polkit Agent";
        After = [ "wayland-session@hyprland.desktop.target" ];
        PartOf = [ "wayland-session@hyprland.desktop.target" ];
      };
      Service = {
        ExecStart = "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent";
        Restart = "on-failure";
        RestartSec = "3s";
      };
      Install.WantedBy = [ "wayland-session@hyprland.desktop.target" ];
    };

    vesktop = {
      Unit = {
        Description = "Vesktop Discord client";
        After = [ "wayland-session@hyprland.desktop.target" "xdg-desktop-portal-hyprland.service" ];
        PartOf = [ "wayland-session@hyprland.desktop.target" ];
        Wants = [ "xdg-desktop-portal-hyprland.service" ];
      };
      Service = {
        ExecStart = "${pkgs.vesktop}/bin/vesktop";
        Environment = [ "NIXOS_OZONE_WL=1" ];
        Restart = "on-failure";
        RestartSec = "5s";
      };
      Install.WantedBy = [ "wayland-session@hyprland.desktop.target" ];
    };

    # easyeffects = {
    #   Unit = {
    #     Description = "EasyEffects audio processor";
    #     After = [ "wayland-session@hyprland.desktop.target" ];
    #     PartOf = [ "wayland-session@hyprland.desktop.target" ];
    #   };
    #   Service = {
    #     ExecStart = "${pkgs.easyeffects}/bin/easyeffects --gapplication-service";
    #     Restart = "on-failure";
    #     RestartSec = "3s";
    #   };
    #   Install.WantedBy = [ "wayland-session@hyprland.desktop.target" ];
    # };

    # openrgb = {
    #   Unit = {
    #     Description = "OpenRGB lighting controller";
    #     After = [ "wayland-session@hyprland.desktop.target" ];
    #     PartOf = [ "wayland-session@hyprland.desktop.target" ];
    #   };
    #   Service = {
    #     ExecStart = "${pkgs.openrgb}/bin/openrgb --startminimized -p default";
    #     Restart = "on-failure";
    #     RestartSec = "3s";
    #   };
    #   Install.WantedBy = [ "wayland-session@hyprland.desktop.target" ];
    # };
  };
}
