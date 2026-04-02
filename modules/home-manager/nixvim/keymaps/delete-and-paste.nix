{
  programs.nixvim.keymaps = [
    {
      mode = "v";
      key = "p";
      action = "\"_dP"; # Delete selection to black hole, then paste
      options.desc = "Paste over selection without overwriting clipboard";
    }
  ];
}
