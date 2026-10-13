{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.my.hypr;
  palette = config.services.wayle.settings.styling.palette;
  togglePopup = pkgs.writeShellScript "wayle-toggle-popup" ''
    export PATH=${
      lib.makeBinPath [
        pkgs.hyprland
        pkgs.uwsm
      ]
    }:$PATH
    exec ${pkgs.python3}/bin/python3 ${./toggle-music.py} "$@"
  '';

  # Custom modules get no per-module theme, so give them the pink split-button look.
  themed =
    module:
    module
    // lib.optionalAttrs (cfg.panel.theme == "pink") {
      border-show = true;
      border-color = palette.fg-muted;
      icon-color = palette.primary;
      icon-bg-color = palette.bg;
      label-color = palette.bg;
      button-bg-color = palette.primary;
    };

  # On, On(<connected devices>) or Off, instead of device names.
  bluetoothStatus = pkgs.writeShellScript "wayle-bluetooth-status" ''
    PATH=${
      lib.makeBinPath [
        pkgs.bluez
        pkgs.coreutils
        pkgs.gnugrep
      ]
    }

    if ! timeout 3 bluetoothctl show 2>/dev/null | grep -q 'Powered: yes'; then
      echo '{"text": "Off", "alt": "off"}'
      exit
    fi
    count=$(timeout 3 bluetoothctl devices Connected 2>/dev/null | grep -c '^Device ')
    if [ "$count" -gt 0 ]; then
      echo "{\"text\": \"On($count)\", \"alt\": \"connected\"}"
    else
      echo '{"text": "On", "alt": "on"}'
    fi
  '';

  # The NetworkManager connection name carrying the default route, not the SSID.
  networkStatus = pkgs.writeShellScript "wayle-network-status" ''
    PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.gawk
        pkgs.gnused
        pkgs.iproute2
        pkgs.jq
        pkgs.networkmanager
      ]
    }

    dev=$(ip -o route show default | awk '{ print $5; exit }')
    if [ -z "$dev" ]; then
      echo '{"text": "Offline", "alt": "offline"}'
      exit
    fi

    { read -r name; read -r type; } < <(nmcli -g GENERAL.CONNECTION,GENERAL.TYPE device show "$dev" 2>/dev/null)
    # nmcli -g backslash-escapes colons and backslashes.
    name=$(sed 's/\\\(.\)/\1/g' <<<"$name")
    name=''${name:-$dev}

    if [ "$type" = wifi ]; then
      signal=$(nmcli -t -f IN-USE,SIGNAL device wifi list --rescan no 2>/dev/null | sed -n 's/^\*://p' | head -n 1)
      jq -cn --arg text "$name" --argjson signal "''${signal:-0}" '{text: $text, alt: "wifi", percentage: $signal}'
    else
      jq -cn --arg text "$name" '{text: $text, alt: "wired"}'
    fi
  '';

  # The playing track, or the last one for 5 minutes after playback stops.
  mediaStatus = pkgs.writeShellScript "wayle-media-status" ''
    PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.jq
        pkgs.playerctl
      ]
    }

    state="''${XDG_RUNTIME_DIR:-/tmp}/wayle-media-last"
    now=$(date +%s)
    playing=$(playerctl -a metadata --format $'{{status}}\t{{title}}\t{{artist}}' 2>/dev/null | grep -m 1 $'^Playing\t')

    if [ -n "$playing" ]; then
      IFS=$'\t' read -r _ title artist <<<"$playing"
      label="$title''${artist:+ - $artist}"
      printf '%s\n%s\n' "$now" "$label" > "$state"
    elif [ -r "$state" ]; then
      { read -r last; read -r label; } < "$state"
      [ $((now - last)) -lt 300 ] || label=""
    else
      label=""
    fi

    jq -cn --arg text "$label" '{text: $text}'
  '';

  desktopLayout = {
    monitor = "*";
    left = [
      "hyprland-workspaces"
      "custom-feishin"
      "systray"
    ];
    center = [ "window-title" ];
    right = [
      "volume"
      "microphone"
      "custom-network"
      "custom-bluetooth"
      "custom-mchose-m7"
      "clock"
      "notifications"
      "dashboard"
    ];
  };

  laptopLayout = {
    monitor = "*";
    left = [
      "hyprland-workspaces"
      "custom-feishin"
      "systray"
      "idle-inhibit"
    ];
    center = [ "window-title" ];
    right = [
      "volume"
      "microphone"
      "custom-network"
      "custom-bluetooth"
      "custom-mchose-m7"
      "battery"
      "clock"
      "notifications"
      "dashboard"
    ];
  };
in
{
  imports = [
    ./themes/pink.nix
    ./steam-presence.nix
  ];

  options.my.hypr.panel.theme = lib.mkOption {
    type = lib.types.str;
    default = "pink";
    description = "Wayle theme to apply. Add a corresponding file in themes/ and guard it with lib.mkIf.";
  };

  config.services.wayle = {
    enable = true;
    settings = {
      bar = {
        layout = [
          (if cfg.layout == "desktop" then desktopLayout else laptopLayout)
        ];
        location = "bottom";
        inset-edge = 0.6;
        inset-ends = lib.mkDefault 0;
        background-opacity = 0;
        button-variant = "block-prefix";
        button-bg-opacity = 75;
        button-label-weight = "medium";
        button-rounding = "md";
        button-border-location = "all";
      };

      general = {
        # Rec Mono Casual with real in-between weights; bar icons are images, not glyphs.
        font-sans = "Recursive Mono Casual Static";
        font-mono = "Recursive Mono Casual Static";
        tearing-mode = true;
      };

      modules = {
        # Bluetooth, network and media replace the built-ins, whose labels
        # cannot be formatted; they still open the built-in dropdowns.
        custom = map themed [
          {
            id = "feishin";
            command = "${mediaStatus}";
            interval-ms = 2000;
            hide-if-empty = false;
            icon-name = "ld-music-symbolic";
            label-show = true;
            label-max-length = 35;
            left-click = "${togglePopup} music";
            right-click = "dropdown:media";
          }
          {
            id = "mchose-m7";
            command = "${pkgs.python3}/bin/python3 ${./mchose-m7-battery.py}";
            interval-ms = 15000;
            hide-if-empty = true;
            icon-name = "ld-mouse-symbolic";
            format = "{{ output }}";
            label-show = true;
          }
          {
            id = "bluetooth";
            command = "${bluetoothStatus}";
            interval-ms = 5000;
            icon-name = "ld-bluetooth-symbolic";
            icon-map = {
              off = "ld-bluetooth-off-symbolic";
              connected = "ld-bluetooth-connected-symbolic";
            };
            left-click = "dropdown:bluetooth";
            right-click = "${togglePopup} bluetooth";
          }
          {
            id = "network";
            command = "${networkStatus}";
            interval-ms = 5000;
            label-max-length = 15;
            icon-name = "cm-wireless-connected-symbolic";
            icon-names = [
              "cm-wireless-signal-weak-symbolic"
              "cm-wireless-signal-ok-symbolic"
              "cm-wireless-signal-good-symbolic"
              "cm-wireless-signal-excellent-symbolic"
            ];
            icon-map = {
              offline = "cm-wireless-offline-symbolic";
              wired = "cm-wired-symbolic";
            };
            left-click = "dropdown:network";
            right-click = "${togglePopup} network";
          }
        ];

        systray.blacklist = [ "feishin_*" ];

        hyprland-workspaces = {
          min-workspace-count = 0;
          monitor-specific = true;
          show-special = false;
          display-mode = "label";
          app-icons-show = false;
          active-indicator = "background";
        };

        window-title = {
          format = "{{ title }}";
          icon-show = true;
          label-show = true;
          label-max-length = 50;
        };

        volume = {
          label-show = true;
          right-click = "${togglePopup} volume";
          scroll-down = "wayle audio output-volume -3";
          scroll-up = "wayle audio output-volume +3";
        };

        microphone.label-show = true;

        clock = {
          format = "%a %b %d  %I:%M %p";
          icon-show = true;
          label-show = true;
        };

        idle-inhibit = {
          icon-inactive = "tb-coffee-off-symbolic";
          icon-active = "tb-coffee-symbolic";
          label-show = false;
        };

        notifications.popup-monitor = "primary";
      };

      osd = {
        enabled = true;
        position = "bottom";
        monitor = "primary";
      };

      # Wallpapers are mpvpaper services from ../wallpapers.nix.
      wallpaper.engine-enabled = false;
    };
  };
}
