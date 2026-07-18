{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.software.apps.vesktop;
  hw = cfg.hardwareVideoEncode;

  insecurePackages = [
    # Temporary Vesktop dependency; remove when Vesktop moves past Electron 40.
    "electron-40.10.5"
  ];
  nixpkgsConfig = pkgs.config or { };
  vesktopPkgs = import pkgs.path {
    localSystem = pkgs.stdenv.hostPlatform.system;
    config = nixpkgsConfig // {
      permittedInsecurePackages =
        (nixpkgsConfig.permittedInsecurePackages or [ ]) ++ insecurePackages;
    };
  };

  launcherEnv =
    cfg.env
    // lib.optionalAttrs hw.enable {
      NIXOS_OZONE_WL = "1";
      LIBVA_DRIVER_NAME = hw.vaDriver;
    }
    // lib.optionalAttrs (hw.enable && hw.driPrime != null) {
      DRI_PRIME = hw.driPrime;
    };

  launcherFlags =
    cfg.extraFlags
    ++ lib.optionals hw.enable [
      "--enable-features=VaapiVideoEncoder,WebRTCPipeWireCapturer"
      "--ignore-gpu-blocklist"
    ];

  wrapperArgs =
    (lib.concatLists (
      lib.mapAttrsToList (name: value: [
        "--set"
        name
        value
      ]) launcherEnv
    ))
    ++ (lib.concatMap (flag: [
      "--add-flags"
      flag
    ]) launcherFlags);

  wrappedPackage = pkgs.symlinkJoin {
    name = "vesktop-wrapped";
    paths = [ cfg.package ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      rm "$out/bin/vesktop"
      makeWrapper ${lib.getExe cfg.package} "$out/bin/vesktop" ${lib.escapeShellArgs wrapperArgs}
    '';
    meta = cfg.package.meta // {
      mainProgram = "vesktop";
    };
  };

  package =
    if launcherEnv != { } || launcherFlags != [ ] then
      wrappedPackage
    else
      cfg.package;
in
{
  options.software.apps.vesktop = {
    enable = lib.mkEnableOption "Vesktop";

    package = lib.mkPackageOption vesktopPkgs "vesktop" { };

    env = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Environment variables to set for the Vesktop launcher.";
    };

    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra command-line flags to append to the Vesktop launcher.";
    };

    hardwareVideoEncode = {
      enable = lib.mkEnableOption "Vesktop hardware video encoding";

      driPrime = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "DRI_PRIME value for Vesktop hardware video encoding.";
      };

      vaDriver = lib.mkOption {
        type = lib.types.str;
        default = "radeonsi";
        description = "LIBVA_DRIVER_NAME value for Vesktop hardware video encoding.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    nixpkgs.config.permittedInsecurePackages = lib.mkAfter insecurePackages;

    environment.systemPackages = [
      package
    ];
  };
}
