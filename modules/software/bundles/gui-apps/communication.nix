{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.software.apps.communication;

  wrapperArgs =
    (lib.concatLists (
      lib.mapAttrsToList (name: value: [
        "--set"
        name
        value
      ]) cfg.vesktop.env
    ))
    ++ (lib.concatMap (flag: [
      "--add-flags"
      flag
    ]) cfg.vesktop.extraFlags);

  wrappedVesktop = pkgs.symlinkJoin {
    name = "vesktop-wrapped";
    paths = [ cfg.vesktop.package ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      rm "$out/bin/vesktop"
      makeWrapper ${lib.getExe cfg.vesktop.package} "$out/bin/vesktop" ${lib.escapeShellArgs wrapperArgs}
    '';
    meta = cfg.vesktop.package.meta // {
      mainProgram = "vesktop";
    };
  };

  vesktopPackage =
    if cfg.vesktop.env != { } || cfg.vesktop.extraFlags != [ ] then
      wrappedVesktop
    else
      cfg.vesktop.package;
in
{
  options.software.apps.communication = {
    enable = lib.mkEnableOption "communication apps";

    vesktop = {
      package = lib.mkPackageOption pkgs "vesktop" { };

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
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      vesktopPackage
      pkgs.thunderbird
    ];
  };
}
