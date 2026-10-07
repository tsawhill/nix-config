{
  config,
  inputs,
  pkgs,
  ...
}:

let
  unstablePkgs = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
{
  networking.firewall.allowedTCPPorts = [ 8080 ];
  services.searx = {
    enable = true;
    # Scraper engines break constantly; unstable tracks upstream's anti-bot fixes.
    package = unstablePkgs.searxng;
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
        # Startpage proxies Google and gets past its bot checks; Google itself often refuses.
        {
          name = "google";
          engine = "google";
          shortcut = "g";
          weight = 1;
          categories = [
            "general"
            "images"
          ];
        }
        {
          name = "startpage";
          engine = "startpage";
          shortcut = "sp";
          weight = 3;
          categories = [
            "general"
            "images"
          ];
        }
        {
          name = "brave";
          engine = "brave";
          shortcut = "brave";
          weight = 1;
          categories = [
            "general"
            "images"
          ];
        }
        {
          name = "mojeek";
          engine = "mojeek";
          shortcut = "mjk";
          weight = 1;
          categories = [ "general" ];
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
          engine = "stackexchange";
          api_site = "stackoverflow";
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
