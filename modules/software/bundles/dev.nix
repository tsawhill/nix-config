{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:
let
  cfg = config.software.dev;
  pkgs-master = import inputs.nixpkgs-master { inherit (pkgs) system config; };

  # Override claude-code vsix hash — marketplace republished 2.1.92 with different content
  claude-code-ext = pkgs-master.vscode-extensions.anthropic.claude-code.overrideAttrs (old: {
    src = old.src.overrideAttrs {
      outputHash = "sha256-f+6xXZVb5sYrmrH7eoon6/QoQaTnBuTnb+YnvszqyKA=";
    };
  });
  chatgptExt = pkgs.vscode-utils.buildVscodeMarketplaceExtension {
    mktplcRef = {
      name = "chatgpt";
      publisher = "openai";
      version = "26.5422.71525"; # put actual version
      sha256 = "sha256-16qkyn5xhh6clchx2c7w4y9ly82kj576dy3ha9q3ljj8sk3sp7gm";
    };
  };
in
{
  options.software.dev.enable = lib.mkEnableOption "development tools";

  # Only apply this config if software.dev.enable = true
  config = lib.mkIf cfg.enable {
    programs.vscode = {
      enable = true;
      package = pkgs.vscodium;
      extensions =
        (with pkgs.vscode-extensions; [
          jnoortheen.nix-ide
          esbenp.prettier-vscode
          ms-python.vscode-pylance
          github.copilot-chat
          claude-code-ext
        ])
        ++ [ openai-chatgpt ];
    };

    environment.systemPackages = with pkgs; [
      nixfmt
      glib
      pkgs-master.claude-code
      codex
    ];
  };
}
