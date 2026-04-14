{ config, ... }:
{
  networking.firewall.allowedTCPPorts = [ 8080 ];
  services.searx = {
    enable = true;
    environmentFile = config.sops.secrets.searx_secret_key.path;
    settings = {
      general = {
        instance_name = "searx-nix";
        debug = false;
      };

      server = {
        port = 8080;
        bind_address = "0.0.0.0";
        method = "GET";
        limiter = false;
      };

      outgoing = {
        request_timeout = 3.0;
        max_request_timeout = 4.0;
      };

      search = {
        safe_search = 0;
        autocomplete = "google";
        default_lang = "en";
      };

      ui = {
        default_theme = "simple";
        default_locale = "en";
        infinite_scroll = true;
      };

      engines = [
        # --- Web ---
        {
          name = "startpage";
          engine = "startpage";
          shortcut = "sp";
          weight = 10;
          categories = [ "general" "images" ];
        }
        {
          name = "bing";
          engine = "bing";
          shortcut = "bi";
          weight = 1;
          categories = [ "general" "images" ];
        }
        {
          name = "brave";
          engine = "brave";
          shortcut = "brave";
          weight = 1;
          categories = [ "general" "images" ];
        }

        # --- Reference ---
        {
          name = "wikipedia";
          engine = "wikipedia";
          shortcut = "wp";
          categories = [ "general" ];
          language = "en";
        }
        {
          name = "wikidata";
          engine = "wikidata";
          shortcut = "wd";
          categories = [ "general" ];
        }
        {
          name = "archive.org";
          engine = "archive.org";
          shortcut = "ao";
          categories = [ "general" ];
        }

        # --- Video ---
        {
          name = "youtube";
          engine = "youtube_noapi";
          shortcut = "yt";
          categories = [ "videos" ];
        }

        # --- Social ---
        {
          name = "reddit";
          engine = "reddit";
          shortcut = "re";
          categories = [ "social media" ];
        }

        # --- Tech / Code ---
        {
          name = "github";
          engine = "github";
          shortcut = "gh";
          categories = [ "it" ];
        }
        {
          name = "gitlab";
          engine = "gitlab";
          shortcut = "gl";
          categories = [ "it" ];
        }
        {
          name = "stackoverflow";
          engine = "stackoverflow";
          shortcut = "st";
          categories = [ "it" ];
        }
        {
          name = "npm";
          engine = "npm";
          shortcut = "npm";
          categories = [ "it" ];
        }
        {
          name = "pypi";
          engine = "pypi";
          shortcut = "pypi";
          categories = [ "it" ];
        }
        {
          name = "dockerhub";
          engine = "docker hub";
          shortcut = "dh";
          categories = [ "it" ];
        }

        # --- Maps ---
        {
          name = "openstreetmap";
          engine = "openstreetmap";
          shortcut = "osm";
          categories = [ "map" ];
        }

        # --- Books ---
        {
          name = "openlibrary";
          engine = "openlibrary";
          shortcut = "ol";
          categories = [ "general" ];
        }
      ];
    };
  };
}
