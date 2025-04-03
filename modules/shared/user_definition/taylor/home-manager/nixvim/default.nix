{ pkgs, ... }:
{
  imports = [
    ./plugins
  ];
  programs.nixvim = {
    enable = true;

    colorschemes.catppuccin.enable = true;
    keymaps = [
      {
        action = "<cmd>Bdelete<CR>";
        key = "<Leader>q";
      }
      {
        action = "<cmd>BufferLineCycleNext<CR>";
        key = "<M-Tab>";
      }
      {
        action = "<cmd>BufferLineCyclePrev<CR>";
        key = "<M-S-Tab>";
      }
      {
        action = "<cmd>resize +2<CR>";
        key = "<M-S-Up>";
      }
      {
        action = "<cmd>resize -2<CR>";
        key = "<M-S-Down>";
      }
      {
        action = "<cmd>vertical resize +2<CR>";
        key = "<M-S-Right>";
      }
      {
        action = "<cmd>vertical resize -2<CR>";
        key = "<M-S-Left>";
      }
      {
        action = "<cmd>wincmd h<CR>";
        key = "<M-Left>";
      }
      {
        action = "<cmd>wincmd l<CR>";
        key = "<M-Right>";
      }
      {
        action = "<cmd>wincmd j<CR>";
        key = "<M-Down>";
      }
      {
        action = "<cmd>wincmd k<CR>";
        key = "<M-Up>";
      }
    ];
    opts = {
      number = true;
    };
  };
}
