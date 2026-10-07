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
      # Brave's results are bad; keep every Brave engine out of the defaults.
      use_default_settings.engines.remove = [
        "brave"
        "brave.images"
        "brave.videos"
        "brave.news"
      ];

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
        # The only two answering normal searches. Startpage and Mojeek are inactive
        # upstream (proof-of-work CAPTCHAs) and the plain Google engine gets refused.
        {
          name = "google cse";
          engine = "google_cse";
          shortcut = "g";
          disabled = false;
        }
        {
          name = "duckduckgo";
          engine = "duckduckgo";
          shortcut = "ddg";
          disabled = false;
        }

        # --- Reference & translation ---
        # Default general engines kept out of normal searches; bangs still work.
        {
          name = "wikipedia";
          engine = "wikipedia";
          shortcut = "wp";
          categories = [ "general" ];
          language = "en";
          disabled = true;
        }
        {
          name = "wikidata";
          engine = "wikidata";
          shortcut = "wd";
          categories = [ "general" ];
          disabled = true;
        }
        {
          name = "lingva";
          engine = "lingva";
          shortcut = "lv";
          disabled = true;
        }
        {
          name = "dictzone";
          engine = "dictzone";
          shortcut = "dc";
          disabled = true;
        }
        {
          name = "mymemory translated";
          engine = "translated";
          shortcut = "tl";
          disabled = true;
        }

        # --- Video ---
        {
          name = "youtube";
          engine = "youtube_noapi";
          shortcut = "yt";
          categories = [ "videos" ];
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
