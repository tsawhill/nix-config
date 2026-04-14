flake:
{ lib, config, pkgs, ... }:

let
  cfg = config.programs.hyprcrosshair;

  system = pkgs.stdenv.hostPlatform.system;
  flakePkgs = flake.packages.${system} or { };
  defaultPackage =
    flakePkgs.default or flakePkgs.hyprcrosshair or (pkgs.callPackage ./package.nix { });

  shapeEnum = {
    "dot" = 0;
    "ring" = 1;
    "square" = 2;
    "cross" = 3;
    "scope" = 4;
    "chevron" = 5;
  };

  formatFloat = f:
    let
      s = toString f;
    in
    if lib.hasInfix "." s then s else "${s}.00";

  formatBool = b: if b then "1" else "0";

  crosshairSettingsType = lib.types.submodule {
    options = {
      output = lib.mkOption {
        type = lib.types.int;
        default = 0;
        description = "Monitor index (0 = first, 1 = second, etc.).";
      };

      outputName = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Monitor name (e.g. DP-1). Takes priority over index.";
      };

      enabled = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether the crosshair is visible.";
      };

      shape = lib.mkOption {
        type = lib.types.enum [ "dot" "ring" "square" "cross" "scope" "chevron" ];
        default = "dot";
        description = "Crosshair shape.";
      };

      color = {
        red = lib.mkOption {
          type = lib.types.float;
          default = 1.0;
          description = "Red component (0.0–1.0).";
        };
        green = lib.mkOption {
          type = lib.types.float;
          default = 1.0;
          description = "Green component (0.0–1.0).";
        };
        blue = lib.mkOption {
          type = lib.types.float;
          default = 1.0;
          description = "Blue component (0.0–1.0).";
        };
        alpha = lib.mkOption {
          type = lib.types.float;
          default = 1.0;
          description = "Alpha component (0.0–1.0).";
        };
      };

      dot = {
        size = lib.mkOption {
          type = lib.types.float;
          default = 2.0;
          description = "Dot radius in pixels.";
        };
      };

      ring = {
        size = lib.mkOption {
          type = lib.types.float;
          default = 20.0;
          description = "Ring/square diameter in pixels.";
        };
        thickness = lib.mkOption {
          type = lib.types.float;
          default = 2.0;
          description = "Ring/square border thickness.";
        };
      };

      cross = {
        thickness = lib.mkOption {
          type = lib.types.float;
          default = 2.0;
          description = "Line thickness for cross/scope.";
        };
        length = lib.mkOption {
          type = lib.types.float;
          default = 10.0;
          description = "Arm length from center.";
        };
        gap = lib.mkOption {
          type = lib.types.float;
          default = 0.0;
          description = "Gap from center.";
        };
        centerDot = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Show center dot on cross/scope.";
        };
      };

      chevron = {
        angle = lib.mkOption {
          type = lib.types.float;
          default = 45.0;
          description = "Chevron opening angle in degrees.";
        };
      };

      outline = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable outline/border around crosshair.";
        };
        size = lib.mkOption {
          type = lib.types.float;
          default = 1.0;
          description = "Outline thickness.";
        };
        feather = lib.mkOption {
          type = lib.types.float;
          default = 1.0;
          description = "Outline feather/blur amount.";
        };
        color = {
          red = lib.mkOption {
            type = lib.types.float;
            default = 0.0;
            description = "Outline red component (0.0–1.0).";
          };
          green = lib.mkOption {
            type = lib.types.float;
            default = 0.0;
            description = "Outline green component (0.0–1.0).";
          };
          blue = lib.mkOption {
            type = lib.types.float;
            default = 0.0;
            description = "Outline blue component (0.0–1.0).";
          };
        };
      };
    };
  };

  renderSettings = s: lib.concatStringsSep "\n" [
    "output=${toString s.output}"
    "output_name=${s.outputName}"
    "enabled=${formatBool s.enabled}"
    "shape=${toString shapeEnum.${s.shape}}"
    "red=${formatFloat s.color.red}"
    "green=${formatFloat s.color.green}"
    "blue=${formatFloat s.color.blue}"
    "alpha=${formatFloat s.color.alpha}"
    "size=${formatFloat s.dot.size}"
    "ring_size=${formatFloat s.ring.size}"
    "ring_thickness=${formatFloat s.ring.thickness}"
    "thickness=${formatFloat s.cross.thickness}"
    "length=${formatFloat s.cross.length}"
    "gap=${formatFloat s.cross.gap}"
    "center_dot=${formatBool s.cross.centerDot}"
    "chevron_angle=${formatFloat s.chevron.angle}"
    "outline=${formatBool s.outline.enable}"
    "outline_size=${formatFloat s.outline.size}"
    "outline_feather=${formatFloat s.outline.feather}"
    "outline_red=${formatFloat s.outline.color.red}"
    "outline_green=${formatFloat s.outline.color.green}"
    "outline_blue=${formatFloat s.outline.color.blue}"
  ];

  renderProfile = index: profile:
    lib.concatStringsSep "\n" [
      "[Profile${toString index}]"
      "name=${profile.name}"
      (renderSettings profile.settings)
    ];

  profilesIni = lib.concatStringsSep "\n\n" (
    [
      "[General]\nactive_profile=${toString cfg.profiles.active}"
    ]
    ++ lib.imap0 renderProfile cfg.profiles.configs
  );

  numProfiles = lib.length cfg.profiles.configs;

  # Script that cycles through profiles at runtime
  cycleScript = pkgs.writeShellScript "hyprcrosshair-cycle" ''
    CONFIG_DIR="''${XDG_CONFIG_HOME:-$HOME/.config}/hyprcrosshair"
    CONFIG="$CONFIG_DIR/config.ini"
    PROFILES="$CONFIG_DIR/profiles.ini"
    STATE="$CONFIG_DIR/.active_profile"

    # Noop if hyprcrosshair not running
    pgrep -x hyprcrosshair > /dev/null 2>&1 || exit 0

    if [ ! -f "$PROFILES" ]; then
      echo "No profiles.ini found" >&2
      exit 1
    fi

    NUM_PROFILES=${toString numProfiles}
    if [ "$NUM_PROFILES" -lt 2 ]; then
      exit 0
    fi

    # Read current profile index
    CURRENT=0
    if [ -f "$STATE" ]; then
      CURRENT=$(cat "$STATE")
    fi

    # Cycle to next
    NEXT=$(( (CURRENT + 1) % NUM_PROFILES ))

    # Extract profile section from profiles.ini
    ${pkgs.gawk}/bin/awk -v idx="$NEXT" '
      BEGIN { in_profile=0; found=0 }
      /^\[Profile/ {
        if (found) exit
        match($0, /\[Profile([0-9]+)\]/, m)
        if (m[1] == idx) { found=1; in_profile=1; next }
        else { in_profile=0 }
      }
      /^\[/ && !/^\[Profile/ { if (found) exit; in_profile=0 }
      in_profile && found && /^name=/ { next }
      in_profile && found && /=/ { print }
    ' "$PROFILES" > "$CONFIG"

    # Save state
    echo "$NEXT" > "$STATE"

    # Reload by kill+relaunch
    pkill -x hyprcrosshair 2>/dev/null
    hyprcrosshair &

    # Get profile name for notification
    PROFILE_NAME=$(${pkgs.gawk}/bin/awk -v idx="$NEXT" '
      /^\[Profile/ {
        match($0, /\[Profile([0-9]+)\]/, m)
        if (m[1] == idx) { getline; sub(/^name=/, ""); print; exit }
      }
    ' "$PROFILES")

    notify-send -t 1500 -u low "Crosshair" "Profile: $PROFILE_NAME"
  '';

in
{
  options.programs.hyprcrosshair = {
    enable = lib.mkEnableOption "hyprcrosshair crosshair overlay for Hyprland";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      description = "The hyprcrosshair package to use.";
    };

    settings = lib.mkOption {
      type = crosshairSettingsType;
      default = { };
      description = "Main crosshair config written to ~/.config/hyprcrosshair/config.ini.";
    };

    profiles = {
      active = lib.mkOption {
        type = lib.types.ints.between 0 2;
        default = 0;
        description = "Active profile index (0–2).";
      };

      configs = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              default = "Default";
              description = "Profile display name.";
            };
            settings = lib.mkOption {
              type = crosshairSettingsType;
              default = { };
              description = "Crosshair settings for this profile.";
            };
          };
        });
        default = [ ];
        description = "Up to 3 crosshair profiles for profiles.ini.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.length cfg.profiles.configs <= 3;
        message = "hyprcrosshair supports a maximum of 3 profiles.";
      }
    ];

    home.packages = [ cfg.package ]
      ++ lib.optional (cfg.profiles.configs != [ ])
        (pkgs.writeShellScriptBin "hyprcrosshair-cycle" (builtins.readFile cycleScript));

    # profiles.ini is read-only reference data — nix-managed
    xdg.configFile."hyprcrosshair/profiles.ini" = lib.mkIf (cfg.profiles.configs != [ ]) {
      text = profilesIni;
    };

    # config.ini must be mutable for runtime profile cycling
    # Activation script writes initial config from active profile
    home.activation.hyprcrosshairConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      config_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/hyprcrosshair"
      mkdir -p "$config_dir"
      cat > "$config_dir/config.ini" << 'NIXEOF'
${
  if cfg.profiles.configs != [ ]
  then renderSettings (lib.elemAt cfg.profiles.configs cfg.profiles.active).settings
  else renderSettings cfg.settings
}
NIXEOF
      echo "${toString cfg.profiles.active}" > "$config_dir/.active_profile"
    '';
  };
}
