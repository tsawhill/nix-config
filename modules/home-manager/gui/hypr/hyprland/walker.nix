{
  lib,
  inputs,
  osConfig,
  pkgs,
  ...
}:
let
  elephantPackages = inputs.elephant.packages.${pkgs.stdenv.hostPlatform.system};

  # Upstream builds the same vendorHash twice under different fixed-output
  # names: elephant-*-go-modules and elephant-providers-*-go-modules. Give the
  # providers module output the daemon's name so Nix shares the already-fetched
  # dependencies instead of downloading every Go module a second time.
  elephantProviders = elephantPackages.elephant-providers.overrideAttrs {
    overrideModAttrs = _: _: {
      name = "${elephantPackages.elephant.name}-go-modules";
    };
  };

  elephantWithProviders = elephantPackages.elephant-with-providers.overrideAttrs {
    buildInputs = [
      elephantPackages.elephant
      elephantProviders
    ];

    installPhase = ''
      mkdir -p $out/bin $out/lib/elephant
      cp ${elephantPackages.elephant}/bin/elephant $out/bin/
      cp -r ${elephantProviders}/lib/elephant/providers $out/lib/elephant/
    '';
  };
in
{
  imports = [ inputs.walker.homeManagerModules.default ];

  programs.elephant.package = elephantWithProviders;

  programs.walker = lib.mkIf (osConfig.my.hypr.launcher == "walker") {
    enable = true;
    package = pkgs.walker;
    runAsService = true;
    config = {
      app_launch_prefix = lib.mkIf osConfig.programs.hyprland.withUWSM "uwsm app --";
      # '>' prefix exclusively triggers runner in normal walker search
      providers.prefixes = [
        {
          prefix = ">";
          provider = "runner";
        }
      ];
    };
  };
}
