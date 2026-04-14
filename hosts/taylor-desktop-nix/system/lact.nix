{
  pkgs,
  lib,
  config,
  ...
}:
let
  # The GPU ID prefix is matched by LACT as "<vendor>:<device>-*".
  # Your dGPU is 1002:744C (RX 7900 XTX) at 0000:03:00.0.
  # You can confirm with: lact cli list-gpus
  dgpuId = "1002:744C";

  # Power cap in watts. Stock TDP for the 7900 XTX is ~355W.
  # 290W is the sweet spot: eliminates SMU hangs with minimal perf impact.
  # Raise toward 330W if stable, lower toward 250W if still crashing.
  powerCapWatts = 260.0;

  lactConfig = {
    daemon = {
      log_level = "info";
      admin_groups = [ "wheel" ];
      disable_clocks_cleanup = false;
    };
    gpus = {
      # Keyed by GPU ID prefix — LACT matches on vendor:device and ignores
      # the rest of the PCI path, so this covers your card regardless of slot.
      "${dgpuId}" = {
        power_cap = powerCapWatts;
        performance_level = "auto";
      };
    };
  };
in
{
  # Enable overdrive so LACT can set power caps outside the default range.
  # This sets amdgpu.ppfeaturemask=0xfffd7fff as a kernel param.
  hardware.amdgpu.overdrive.enable = true;

  services.lact.enable = true;

  # Write the config declaratively. LACT hot-reloads on file changes,
  # but a full daemon restart on rebuild ensures settings are always applied.
  environment.etc."lact/config.yaml" = {
    text = lib.generators.toYAML { } lactConfig;
    # Root-owned, readable by the daemon
    mode = "0644";
  };

  # Force lactd to restart whenever the config changes (i.e. on nixos-rebuild).
  systemd.services.lactd = {
    restartTriggers = [ config.environment.etc."lact/config.yaml".source ];
  };
}
