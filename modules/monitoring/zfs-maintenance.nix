{ config, lib, ... }:

let
  cfg = config.my.monitoring.zfsMaintenance;
in
{
  options.my.monitoring.zfsMaintenance = {
    enable = lib.mkEnableOption "ZFS scrub and trim maintenance";

    scrub = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to enable automatic ZFS scrubs.";
      };

      interval = lib.mkOption {
        type = lib.types.str;
        default = "monthly";
        description = "systemd calendar interval for automatic ZFS scrubs.";
      };

      pools = lib.mkOption {
        type = lib.types.nullOr (lib.types.listOf lib.types.str);
        default = null;
        description = "Optional list of ZFS pools to scrub.";
      };
    };

    trim = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to enable automatic ZFS trim.";
      };

      interval = lib.mkOption {
        type = lib.types.str;
        default = "monthly";
        description = "systemd calendar interval for automatic ZFS trim.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.zfs = {
      autoScrub = {
        enable = cfg.scrub.enable;
        interval = cfg.scrub.interval;
      }
      // lib.optionalAttrs (cfg.scrub.pools != null) {
        pools = cfg.scrub.pools;
      };

      trim = {
        enable = cfg.trim.enable;
        interval = cfg.trim.interval;
      };
    };
  };
}
