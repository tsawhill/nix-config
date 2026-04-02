{
  programs.nixvim.plugins = {
    which-key = {
      enable = true;
      settings = {
        spec = [
          {
            __unkeyed-1 = "<leader>";
            group = "Leader"; # This gives the root menu a name
          }
        ];
      };
    };
  };
}
