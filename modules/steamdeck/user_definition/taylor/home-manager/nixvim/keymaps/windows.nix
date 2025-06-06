{
  programs.nixvim.keymaps = [
    # Resize Windows
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

    # Navigate windows with cursor
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
}
