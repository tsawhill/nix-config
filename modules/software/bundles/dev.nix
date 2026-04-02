{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.software.dev;
in
{
  options.software.dev.enable = lib.mkEnableOption "development tools";

  # Only apply this config if software.dev.enable = true
  config = lib.mkIf cfg.enable {
    programs.vscode = {
      enable = true;
      package = pkgs.vscodium;
      extensions = with pkgs.vscode-extensions; [
        jnoortheen.nix-ide
        esbenp.prettier-vscode
        ms-python.vscode-pylance
        github.copilot-chat
        # anthropic.claude-code
      ];
    };

    environment.systemPackages = with pkgs; [
      nixfmt
      glib
      # claude-code
    ];
  };
}
