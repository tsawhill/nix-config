{
  imports = [
    ./plugins
    ./keymaps
  ];
  programs.nixvim = {
    enable = true;

    colorschemes.catppuccin.enable = true;
    opts = {
      number = true;
    };
  };
}
