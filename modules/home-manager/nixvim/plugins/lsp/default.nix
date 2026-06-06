{ config, lib, ... }:
{
  imports = [
    ./python.nix
    ./nix.nix
    ./lua.nix
    ./markdown.nix
    ./bash.nix
    ./json.nix
  ];

  config = lib.mkIf config.my.nixvim.full {
    programs.nixvim.plugins = {
      lsp-format = {
        enable = true;
      };
      lsp = {
        enable = true;
      };
    };
  };
}
