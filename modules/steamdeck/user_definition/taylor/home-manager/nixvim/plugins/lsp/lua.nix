{
  programs.nixvim.plugins = {
    lsp = {
      servers = {
        lua_ls = {
          enable = true;
          settings.telemetry.enable = false;
        };
      };
    };
  };
}
