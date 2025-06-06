{
  programs.nixvim.keymaps = [
    # Close buffer without closing window (vim-bbye)
    {
      action = "<cmd>Bdelete<CR>";
      key = "<Leader>q";
    }

    # Cycle forward and backwards across buffers
    {
      action = "<cmd>BufferLineCycleNext<CR>";
      key = "<M-Tab>";
    }
    {
      action = "<cmd>BufferLineCyclePrev<CR>";
      key = "<M-S-Tab>";
    }
  ];
}
