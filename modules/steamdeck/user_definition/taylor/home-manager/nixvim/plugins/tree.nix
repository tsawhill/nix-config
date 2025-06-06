{
  programs.nixvim.plugins = {
    neo-tree = {
      enable = true;
      closeIfLastWindow = true;
      extraOptions = {
        window = {
          width = 25;
        };
      };
    };
  };
}
