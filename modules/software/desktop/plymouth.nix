# Catppuccin boot splash, plus the console silencing that makes it worth having.
#
# Plymouth owns the screen from initrd through to the display manager. Kernel and
# udev log spam tears straight through the splash, so the silencing is part of the
# same feature rather than a separate opinion - hence `silenceKernel` defaulting on.
# Nothing is lost: this mutes the console only, and journald still has every message.
{
  lib,
  pkgs,
  config,
  ...
}:

let
  cfg = config.desktop.plymouth;
in
{
  options.desktop.plymouth = {
    enable = lib.mkEnableOption "Plymouth boot splash (Catppuccin)";

    flavor = lib.mkOption {
      type = lib.types.enum [
        "latte"
        "frappe"
        "macchiato"
        "mocha"
      ];
      default = "mocha";
      description = "Catppuccin flavor. The theme installs as catppuccin-<flavor>.";
    };

    silenceKernel = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Quiet the kernel, udev and initrd console output so the splash stays clean.";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.plymouth = {
      enable = true;
      theme = "catppuccin-${cfg.flavor}";
      themePackages = [ (pkgs.catppuccin-plymouth.override { variant = cfg.flavor; }) ];
    };

    # boot.consoleLogLevel becomes the kernel's `loglevel=` parameter, so it is set
    # here rather than duplicated in kernelParams.
    boot.consoleLogLevel = lib.mkIf cfg.silenceKernel 0;
    boot.initrd.verbose = lib.mkIf cfg.silenceKernel false;

    boot.kernelParams = lib.mkIf cfg.silenceKernel [
      "quiet"
      "splash"
      "udev.log_level=3"
      # `auto` stays silent on a normal boot but still shows systemd status in the
      # initrd when something actually fails - worth keeping when the screen is
      # otherwise covered.
      "rd.systemd.show_status=auto"
    ];
  };
}
