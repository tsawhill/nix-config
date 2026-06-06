{ config, lib, ... }:
{
  config = lib.mkIf config.my.nixvim.full {
    programs.nixvim.plugins = {
      noice = {
        enable = true;
        settings = {
          backend = "cmp";
        };
      };
    };
  };
}
