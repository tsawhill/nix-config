{ config, lib, ... }:
{
  config = lib.mkIf config.my.nixvim.full {
    programs.nixvim.plugins = {
      lsp = {
        servers = {
          bashls = {
            enable = true;
          };
        };
      };
    };
  };
}
