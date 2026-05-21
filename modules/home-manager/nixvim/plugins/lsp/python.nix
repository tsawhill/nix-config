{ pkgs, ... }:
let
  pylspPackage = pkgs.python3Packages.python-lsp-server.overridePythonAttrs (_old: {
    # 1.14.0 currently times out/hangs in pytest on Python 3.13, blocking deploys.
    doCheck = false;
  });
in
{
  programs.nixvim.plugins = {
    lsp = {
      servers = {
        pylsp = {
          enable = true;
          package = pylspPackage;
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
