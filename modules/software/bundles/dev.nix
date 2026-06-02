{
  pkgs,
  lib,
  config,
  nix-vscode-extensions-input,
  ...
}:
let
  cfg = config.software.dev;
in
{
  options.software.dev.enable = lib.mkEnableOption "development tools";

  config = lib.mkIf cfg.enable {
    nixpkgs.overlays = [ nix-vscode-extensions-input.overlays.default ];

    programs.vscode = {
      enable = true;
      package = pkgs.vscodium;
      extensions = [
        pkgs.vscode-marketplace.jnoortheen.nix-ide
        pkgs.vscode-marketplace.esbenp.prettier-vscode
        pkgs.vscode-marketplace.ms-python.vscode-pylance
        pkgs.open-vsx.jeanp413.open-remote-ssh
        pkgs.vscode-marketplace.github.copilot-chat
        pkgs.vscode-marketplace.anthropic.claude-code
        pkgs.vscode-marketplace.openai.chatgpt
      ];
    };

    environment.systemPackages = with pkgs; [
      nixfmt
      glib
      claude-code
      codex
    ];
  };
}
