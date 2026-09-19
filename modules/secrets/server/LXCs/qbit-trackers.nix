{ config, lib, ... }:

let
  cfg = config.my.secrets.qbit-trackers;

  # Announce-URL keywords qbit-manage matches on. They identify which private
  # trackers are in use, so they stay out of the repo; the share limit groups
  # that consume them do not and live in the host config.
  mkTrackerSecret = name: {
    sopsFile = ./qbit-trackers.yaml;
    key = name;
    mode = "0400";
  };
in
{
  options.my.secrets.qbit-trackers = {
    enable = lib.mkEnableOption "Secrets for qbit-manage tracker keywords";

    tiers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "qbit_tracker_t1"
        "qbit_tracker_t2"
        "qbit_tracker_t3"
      ];
      description = "Secret keys to declare, one per tracker tier. Extend as tiers are added.";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets = lib.genAttrs cfg.tiers mkTrackerSecret;
  };
}
