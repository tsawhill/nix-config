{
  programs.nixvim.plugins = {
    cmp = {
      enable = true;
      autoEnableSources = true;
      settings.sources = [
        { name = "nvim-lsp"; }
        { name = "vim-lsp"; }
        { name = "git"; }
        { name = "buffer"; }
        { name = "cmdline"; }
      ];
    };
    cmp-nvim-lsp = {
      enable = true;
    };
    cmp-vim-lsp = {
      enable = true;
    };
    cmp-git = {
      enable = true;
    };
  };
}
