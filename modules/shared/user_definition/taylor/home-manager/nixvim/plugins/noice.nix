{
  programs.nixvim.plugins = {
    noice = {
      enable = true;
      settings = {
        backend = "cmp";
      };
    };
  };
}
