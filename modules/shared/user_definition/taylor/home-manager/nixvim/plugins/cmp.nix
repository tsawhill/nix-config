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
      settings.mapping = {
        "<C-Space>" = "cmp.mapping.complete()";
        "<C-d>" = "cmp.mapping.scroll_docs(-4)";
        "<C-e>" = "cmp.mapping.close()";
        "<C-f>" = "cmp.mapping.scroll_docs(4)";
        "<CR>" = "cmp.mapping.confirm({ select = true })";
        "<S-Tab>" = "cmp.mapping(cmp.mapping.select_prev_item(), {'i', 's'})";
        "<Tab>" = "cmp.mapping(cmp.mapping.select_next_item(), {'i', 's'})";
      };
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
