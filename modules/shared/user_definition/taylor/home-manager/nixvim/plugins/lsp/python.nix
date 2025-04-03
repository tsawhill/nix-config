{
  programs.nixvim.plugins = {
    lsp = {
      servers = {
        pylsp = {
          enable = true;
          settings.plugins = {
            black.enabled = true;
            flake8.enabled = false;
            isort.enabled = true;
            jedi.enabled = false;
            mccabe.enabled = false;
            pycodestyle.enabled = false;
            pydocstyle.enabled = true;
            pyflakes.enabled = false;
            pylint.enabled = true;
            rope.enabled = false;
            yapf.enabled = false;
          };
        };
      };
    };
  };
}
