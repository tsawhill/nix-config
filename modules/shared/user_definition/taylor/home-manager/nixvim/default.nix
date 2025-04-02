{
  programs.nixvim = {
    enable = true;

    colorschemes.catppuccin.enable = true;
    plugins = {
      nix = {
        enable = true;
      };
      telescope = {
        enable = true;
      };
      treesitter = {
        enable = true;
      };
      lualine = {
        enable = true;
      };
      cmp = {
        enable = true;
      };
      cmp-nvim-lsp = {
        enable = true;
      };
      lsp = {
        enable = true;
        servers = {
          bashls.enable = true;
          jsonls.enable = true;
          lua_ls = {
            enable = true;
            settings.telemetry.enable = false;
          };
          marksman.enable = true;
          nil_ls = {
            enable = true;
            # settings = {
            #   formatting.command = [ "nixpkgs-fmt" ];
            # };
          };
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
      lsp-format = {
        enable = true;
      };
      commentary = {
        enable = true;
      };
      neo-tree = {
        enable = true;
        closeIfLastWindow = true;
        extraOptions = {
          window = {
            width = 25;
          };
        };
      };
      web-devicons = {
        enable = true;
      };
      which-key = {
        enable = true;
      };
      bufferline = {
        enable = true;
      };
    };
    keymaps = [
      {
        action = "<cmd>vertical resize +2<CR>";
        key = "<M-S-Right>";
      }
      {
        action = "<cmd>vertical resize -2<CR>";
        key = "<M-S-Left>";
      }
      {
        action = "<cmd>wincmd h<CR>";
        key = "<M-Left>";
      }
      {
        action = "<cmd>wincmd l<CR>";
        key = "<M-Right>";
      }
    ];
    opts = {
      number = true;
      relativenumber = true;
    };
  };
}
