{ config, lib, ... }:
{
  config = lib.mkIf config.my.nixvim.full {
    programs.nixvim.plugins = {
      nix = {
        enable = true;
      };
      lsp = {
        servers = {
          nixd = {
            enable = true;
          };
        };
      };
    };
  };
}
