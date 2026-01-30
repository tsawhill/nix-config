{
  programs.nixvim.plugins = {
    neo-tree = {
      enable = true;
      settings = {
        close_if_last_window = true;
        window = {
          width = 25;
        };
      };
    };
  };
}
