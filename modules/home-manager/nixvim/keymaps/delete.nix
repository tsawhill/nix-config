{
  programs.nixvim.keymaps = [
    {
      mode = "v"; # Visual mode only
      key = "x";
      action = "\"_d";
      options = {
        desc = "Delete selection to black hole register";
        silent = true;
      };
    }
  ];
}
