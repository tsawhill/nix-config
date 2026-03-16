{
  config,
  pkgs,
  lib,
  ...
}:
/**
  Garbage Collection Configuration Module
  * @param generations - The number of recent system generations to preserve.
  Note: Uses the '+N' syntax in nix-env to ensure a fixed count is kept
  regardless of the age of the generations.
*/
let
  cfg = config.my.garbage.collection;
in
{
  options.my.garbage.collection = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to enable automatic garbage collection and generation pruning.";
    };

    generations = lib.mkOption {
      type = lib.types.int;
      default = 5;
      description = "The number of recent system generations to preserve.";
    };

    gcFrequency = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      description = "How often to run the GC (systemd calendar format).";
    };

    pruneFrequency = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      description = "How often to run the pruning (systemd calendar format).";
    };
  };

  config = lib.mkIf cfg.enable {
    nix.gc = {
      automatic = true;
      dates = cfg.gcFrequency;
      options = "--delete-older-than 7d";
      randomizedDelaySec = "6h";
    };

    systemd.services.prune-nixos-generations = {
      description = "Prune NixOS system profile to keep last ${toString cfg.generations} generations";
      startAt = cfg.pruneFrequency;
      before = [ "nix-gc.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.nix}/bin/nix-env -p /nix/var/nix/profiles/system --delete-generations +${toString cfg.generations}";
      };
      wantedBy = [ "multi-user.target" ];
    };
  };
}
