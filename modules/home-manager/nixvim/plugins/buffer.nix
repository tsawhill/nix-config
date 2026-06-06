{ config, lib, ... }:
{
  config = lib.mkIf config.my.nixvim.full {
    programs.nixvim.plugins = {
    bufferline = {
      enable = true;
    };
    vim-bbye = {
      enable = true;
    };
    };
  };
}
