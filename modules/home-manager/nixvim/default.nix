{
  lib,
  nixvim-input,
  ...
}:
{
  imports = [
    nixvim-input.homeModules.nixvim
    ./plugins
    ./keymaps
  ];

  options.my.nixvim.full = lib.mkEnableOption "the full Nixvim plugin set with LSPs and heavier language tooling";

  config = {
    programs.nixvim = {
      enable = true;
      nixpkgs.useGlobalPackages = true;
      clipboard.register = "unnamedplus";
      globals.mapleader = " "; # Sets leader to Space
      colorschemes.catppuccin = {
        enable = true;
        settings.flavour = "frappe";
      };
      opts = {
        number = true;
      };
      # Inject the OSC 52 clipboard logic for SSH sessions natively
      extraConfigLua = ''
        if vim.env.SSH_TTY then
          vim.g.clipboard = {
            name = 'OSC 52',
            copy = {
              ['+'] = require('vim.ui.clipboard.osc52').copy('+'),
              ['*'] = require('vim.ui.clipboard.osc52').copy('*'),
            },
            paste = {
              ['+'] = require('vim.ui.clipboard.osc52').paste('+'),
              ['*'] = require('vim.ui.clipboard.osc52').paste('*'),
            },
          }
        end
      '';
    };
  };
}
