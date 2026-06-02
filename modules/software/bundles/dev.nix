{
  pkgs,
  lib,
  config,
  nix-vscode-extensions-input,
  ...
}:
let
  cfg = config.software.dev;
  marketplace = nix-vscode-extensions-input.extensions.${pkgs.stdenv.hostPlatform.system}.vscode-marketplace;
in
{
  options.software.dev.enable = lib.mkEnableOption "development tools";

  config = lib.mkIf cfg.enable {
    programs.vscode = {
      enable = true;
      package = pkgs.vscodium;
      extensions = [
        marketplace.jnoortheen.nix-ide
        marketplace.esbenp.prettier-vscode
        marketplace.ms-python.vscode-pylance
        marketplace.jeanp413.open-remote-ssh
        marketplace.github.copilot-chat
        marketplace.anthropic.claude-code
        marketplace.openai.chatgpt
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
