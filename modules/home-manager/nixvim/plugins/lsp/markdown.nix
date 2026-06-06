{ config, lib, ... }:
{
  config = lib.mkIf config.my.nixvim.full {
    programs.nixvim.plugins = {
      lsp = {
        servers = {
          marksman = {
            enable = true;
          };
        };
      };
    };
  };
}
