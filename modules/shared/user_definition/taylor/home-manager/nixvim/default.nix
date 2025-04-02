{
  programs.nixvim = {
    enable = true;

    colorschemes.catppuccin.enable = true;
    plugins = {
      nix = {
        enable = true;
      };
      telescope = {
        enable = true;
      };
      treesitter = {
        enable = true;
      };
      lualine = {
        enable = true;
      };
      cmp = {
        enable = true;
      };
      cmp-nvim-lsp = {
        enable = true;
      };
      lsp = {
        enable = true;
      };
      commentary = {
        enable = true;
      };
      neo-tree = {
        enable = true;
        closeIfLastWindow = true;
        extraOptions = {
          window = {
            width = 25;
          };
        };
      };
      web-devicons = {
        enable = true;
      };
      which-key = {
        enable = true;
      };
      bufferline = {
        enable = true;
      };
    };
    keymaps = [
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
    ];
  };
}
