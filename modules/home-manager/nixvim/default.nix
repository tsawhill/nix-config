{ inputs, nixvim-input, ... }:
{
  imports = [
    nixvim-input.homeModules.nixvim
    ./plugins
    ./keymaps
  ];
  programs.nixvim = {
    enable = true;
    clipboard.register = "unnamedplus";
    colorschemes.catppuccin = {
      enable = true;
      settings.flavour = "frappe";
    };
    opts = {
      number = true;
    };
  };
}
