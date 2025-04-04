{
  imports = [
    ./plugins
    ./keymaps
  ];
  programs.nixvim = {
    enable = true;

    colorschemes.catppuccin = {
      enable = true;
      settings.flavour = "frappe";
    };
    opts = {
      number = true;
    };
  };
}
