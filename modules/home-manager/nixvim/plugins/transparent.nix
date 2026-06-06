{ config, lib, ... }:
{
  config = lib.mkIf config.my.nixvim.full {
    programs.nixvim.plugins = {
      transparent = {
        enable = true;
      };
    };
  };
}
