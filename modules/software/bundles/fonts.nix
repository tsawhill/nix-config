{
  pkgs,
  lib,
  config,
  ...
}:
{
  options.software.fonts.enable = lib.mkEnableOption "fonts";

  config = lib.mkIf config.software.fonts.enable {
    fonts.packages = with pkgs; [
      roboto
      ubuntu-sans
      nerd-fonts.jetbrains-mono
      nerd-fonts.geist-mono
      nerd-fonts.fira-code
      nerd-fonts.sauce-code-pro
      nerd-fonts.departure-mono
      nerd-fonts.daddy-time-mono
      nerd-fonts.victor-mono
    ];
  };
}
