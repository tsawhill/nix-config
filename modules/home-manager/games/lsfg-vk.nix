{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  cfg = osConfig.software.games.lsfgVk;
  toml = pkgs.formats.toml { };
  dllPath =
    if cfg.dllPath != null then
      cfg.dllPath
    else
      "${config.home.homeDirectory}/.local/share/Steam/steamapps/common/Lossless Scaling/Lossless.dll";
in
{
  config = lib.mkIf cfg.enable {
    xdg.configFile."lsfg-vk/conf.toml".source = toml.generate "lsfg-vk-conf.toml" {
      version = 1;
      global.dll = dllPath;
      game = cfg.generatedProfiles;
    };
  };
}
