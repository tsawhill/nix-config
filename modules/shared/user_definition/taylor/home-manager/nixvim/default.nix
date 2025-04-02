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
      };
      web-devicons = {
        enable = true;
      };
      # harpoon = {
      # 	enable = true;
      # };
      # which-key = {
      #   enable = true;
      # };
      bufferline = {
        enable = true;
      };
    };
  };
}
