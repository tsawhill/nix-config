{
  imports = [
    ./plugins
    ./keymaps
  ];
  programs.nixvim = {
    enable = true;

    colorschemes.catppuccin = {
      enable = true;
      flavour = "frappe";
    };
    opts = {
      number = true;
    };
  };
}
