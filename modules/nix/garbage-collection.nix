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
      default = 3;
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

    prunePerHostProfiles = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Also prune /nix/var/nix/profiles/per-host/*/system (Colmena builder machines).";
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
      };
      script =
        let
          nix-env = "${pkgs.nix}/bin/nix-env";
          keep = "+${toString cfg.generations}";
        in
        ''
          # Prune local system profile
          ${nix-env} -p /nix/var/nix/profiles/system --delete-generations ${keep}
        ''
        + lib.optionalString cfg.prunePerHostProfiles ''
          # Prune Colmena per-host profiles (builder machine). These are laid out
          # flat as <host>-<N>-link with no base symlink, so nix-env cannot resolve
          # a current generation: `--delete-generations +N` silently no-ops and
          # `old` deletes every generation including the newest. Enumerate and
          # delete by explicit number instead.
          for prof in $(${pkgs.findutils}/bin/find /nix/var/nix/profiles/per-host \
            -maxdepth 1 -name '*-[0-9]*-link' -printf '%f\n' 2>/dev/null \
            | ${pkgs.gnused}/bin/sed 's/-[0-9]\+-link$//' | ${pkgs.coreutils}/bin/sort -u); do
            p=/nix/var/nix/profiles/per-host/"$prof"
            stale=$(${nix-env} -p "$p" --list-generations 2>/dev/null \
              | ${pkgs.gawk}/bin/awk '{print $1}' \
              | ${pkgs.coreutils}/bin/head -n -${toString cfg.generations})
            if [ -n "$stale" ]; then
              echo "Pruning $prof: dropping generations $(echo $stale)"
              ${nix-env} -p "$p" --delete-generations $stale
            fi
          done
        '';
      wantedBy = [ "multi-user.target" ];
    };
  };
}
