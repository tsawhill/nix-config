{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.software.apps.gaming;
  profileFiles = lib.filterAttrs (
    name: type: type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix"
  ) (builtins.readDir ./.);

  # A control can sit on more than one physical button -- the MiniHost reports
  # Start on two -- so a bare index is accepted and widened to a list.
  buttonType = lib.types.coercedTo lib.types.ints.unsigned (index: [ index ]) (
    lib.types.listOf lib.types.ints.unsigned
  );

  axisType = lib.types.submodule {
    options = {
      member = lib.mkOption {
        type = lib.types.str;
        example = "lRx";
        description = "DIJOYSTATE2 member the axis arrives on.";
      };
      min = lib.mkOption {
        type = lib.types.int;
        description = "Logical minimum from the HID report descriptor.";
      };
      max = lib.mkOption {
        type = lib.types.int;
        description = "Logical maximum from the HID report descriptor.";
      };
    };
  };

  profileType = lib.types.submodule {
    options = {
      usb = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.submodule {
            options = {
              vendor = lib.mkOption {
                type = lib.types.strMatching "[0-9a-f]{4}";
                example = "1209";
              };
              product = lib.mkOption {
                type = lib.types.strMatching "[0-9a-f]{4}";
                example = "2882";
              };
            };
          }
        );
        default = null;
        description = ''
          USB IDs in lowercase hex. Drives the hidraw uaccess rule that Wine's
          raw HID path and guitar-map both need, plus the Steam client
          exclusion. Null skips both.
        '';
      };

      sdl = lib.mkOption {
        type = lib.types.str;
        description = "SDL GameController mapping line recorded by guitar-map.";
      };

      dinput = lib.mkOption {
        type = lib.types.submodule {
          options = {
            buttons = lib.mkOption {
              type = lib.types.attrsOf buttonType;
              default = { };
              example = {
                a = 0;
                start = [
                  7
                  11
                ];
              };
              description = "SDL control name to rgbButtons index.";
            };
            povs = lib.mkOption {
              type = lib.types.attrsOf lib.types.ints.unsigned;
              default = { };
              example = {
                dpup = 0;
              };
              description = "SDL control name to rgdwPOV index.";
            };
            axes = lib.mkOption {
              type = lib.types.attrsOf axisType;
              default = { };
              description = "SDL control name to the DirectInput axis carrying it.";
            };
          };
        };
        default = { };
        description = ''
          DirectInput layout measured by guitar-map from the raw HID reports,
          rendered into `guitarShimConfig` for xinput-guitar-dll. Wine numbers
          these by HID declaration order, so they deliberately do not match the
          SDL button numbers in `sdl`. Keys name the XInput control the shim
          drives, so a whammy is `rightx` even when its SDL binding is `leftx`.
          A profile with no layout is skipped by the shim, which says so in the
          game's log rather than binding another guitar's table.
        '';
      };
    };
  };

  usbProfiles = lib.filter (profile: profile.usb != null) (lib.attrValues cfg.guitarProfiles);

  hasLayout =
    profile: profile.dinput.buttons != { } || profile.dinput.povs != { } || profile.dinput.axes != { };

  # One GUITAR_SHIM_CONFIG line per guitar, in the vocabulary xinput-guitar-dll
  # parses: `vid:pid control=bN[,bN] control=pN control=<member>:<min>:<max>`.
  shimLine =
    profile:
    lib.concatStringsSep " " (
      [ "${profile.usb.vendor}:${profile.usb.product}" ]
      ++ lib.mapAttrsToList (
        control: indices: "${control}=" + lib.concatMapStringsSep "," (index: "b${toString index}") indices
      ) profile.dinput.buttons
      ++ lib.mapAttrsToList (control: index: "${control}=p${toString index}") profile.dinput.povs
      ++ lib.mapAttrsToList (
        control: axis: "${control}=${axis.member}:${toString axis.min}:${toString axis.max}"
      ) profile.dinput.axes
    );

  shimProfiles = lib.filter (profile: profile.usb != null && hasLayout profile) (
    lib.attrValues cfg.guitarProfiles
  );
in
{
  imports = [
    ../packages/guitar-map.nix
  ]
  ++ map (name: ./. + "/${name}") (builtins.attrNames profileFiles);

  options.software.apps.gaming = {
    guitarProfiles = lib.mkOption {
      type = lib.types.attrsOf profileType;
      default = { };
      description = ''
        Guitars recorded by guitar-map, one entry per SDL GUID. Each profile is
        the single source for that device's SDL mapping, hidraw rule, Steam
        exclusion and DirectInput layout.
      '';
    };
    guitarShimConfig = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        Derived GUITAR_SHIM_CONFIG for xinput-guitar-dll: one line per guitar
        that has both USB IDs and a measured DirectInput layout. The Guitar Hero
        launchers export it; a guitar missing from it is one the DLL will not
        bind, which the game's log names explicitly.
      '';
    };
    sdlGameControllerMappings = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "SDL controller mappings, contributed by guitar profiles and host modules.";
    };
    steamIgnoredGuitarDevices = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "0x1209/0x2882" ];
      description = "Guitar VID/PID pairs hidden from the Steam client only.";
    };
  };

  config = lib.mkIf cfg.enable {
    software.guitarMap.enable = lib.mkDefault true;

    software.apps.gaming = {
      guitarShimConfig = lib.concatMapStrings (profile: shimLine profile + "\n") shimProfiles;
      sdlGameControllerMappings = map (profile: profile.sdl) (lib.attrValues cfg.guitarProfiles);
      steamIgnoredGuitarDevices = map (
        profile: "0x${profile.usb.vendor}/0x${profile.usb.product}"
      ) usbProfiles;
    };

    # Wine's raw HID path and guitar-map's DirectInput capture both read the
    # hidraw node directly, which is otherwise root-only.
    services.udev.extraRules = lib.concatMapStrings (profile: ''
      KERNEL=="hidraw*", ATTRS{idVendor}=="${profile.usb.vendor}", ATTRS{idProduct}=="${profile.usb.product}", GROUP="input", MODE="0660", TAG+="uaccess"
    '') usbProfiles;

    # pam_env's file holds one line per variable, so mappings cannot be inlined
    # in SDL_GAMECONTROLLERCONFIG once there is more than one: the newline
    # truncates the entry and every later mapping is parsed as a stray line.
    environment.sessionVariables = lib.optionalAttrs (cfg.sdlGameControllerMappings != [ ]) {
      SDL_GAMECONTROLLERCONFIG_FILE = toString (
        pkgs.writeText "sdl-gamecontrollerdb.txt" (
          lib.concatMapStrings (mapping: mapping + "\n") cfg.sdlGameControllerMappings
        )
      );
    };

    # mk-game-launcher removes this filter so launched games see the guitars.
    programs.steam.package = lib.mkIf (cfg.steamIgnoredGuitarDevices != [ ]) (
      pkgs.steam.override {
        extraEnv.SDL_GAMECONTROLLER_IGNORE_DEVICES = lib.concatStringsSep "," (
          lib.unique cfg.steamIgnoredGuitarDevices
        );
      }
    );
  };
}
