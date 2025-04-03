{
  programs.nixvim.plugins = {
    nix = {
      enable = true;
    };
    lsp = {
      servers = {
        nixd = {
          enable = true;
        };
      };
    };
  };
}
