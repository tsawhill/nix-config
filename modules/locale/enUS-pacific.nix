{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Set your time zone.
  time.timeZone = "America/Los_Angeles";

  # Use the real tzdata store path so sandboxed applications such as Proton's
  # pressure-vessel runtime can resolve it. Also export the zone explicitly for
  # applications that do not derive it reliably from /etc/localtime.
  environment.sessionVariables = {
    TZ = config.time.timeZone;
    TZDIR = lib.mkForce "${pkgs.tzdata}/share/zoneinfo";
  };

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };
}
