{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.software.apps.gaming;
  minihostSdlMapping =
    "0300bf27091200008228000001010000,MiniHost GH Guitar,type:guitar,a:b0,b:b1,x:b3,y:b4,back:b10,guide:b12,start:b11,leftshoulder:b6,rightshoulder:b7,dpup:h0.1,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,leftx:a0,lefty:a1,lefttrigger:b8,righttrigger:b9,platform:Linux";

  minihostWineGuitarFix = pkgs.writeShellApplication {
    name = "minihost-wine-guitar-fix";
    runtimeInputs = [ pkgs.wineWow64Packages.stable ];
    text = ''
      set -euo pipefail

      usage() {
        cat <<'EOF'
      Usage:
        minihost-wine-guitar-fix [--xinput-guitar|--raw] [path/to/wine-prefix]

      Applies WineBus controller settings for the RetroCultMods MiniHost GH Guitar.
      The default --xinput-guitar mode uses Wine's SDL controller backend and
      exposes the MiniHost as an XInput guitar instead of a normal gamepad.
      Set WINE=/path/to/wine first if you want a specific Wine binary.
      EOF
      }

      if [ "''${1:-}" = "--help" ] || [ "''${1:-}" = "-h" ]; then
        usage
        exit 0
      fi

      mode="xinput-guitar"
      case "''${1:-}" in
        --xinput-guitar)
          mode="xinput-guitar"
          shift
          ;;
        --raw)
          mode="raw"
          shift
          ;;
      esac

      if [ "$#" -gt 1 ]; then
        usage >&2
        exit 2
      fi

      if [ "$#" -eq 1 ]; then
        export WINEPREFIX="$1"
      fi

      wine_cmd="''${WINE:-wine}"
      winebus_key='HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\winebus'
      dll_overrides_key='HKEY_CURRENT_USER\Software\Wine\DllOverrides'

      if [ "$mode" = "xinput-guitar" ]; then
        "$wine_cmd" reg add "$winebus_key" /v "Enable SDL" /t REG_DWORD /d 1 /f
        "$wine_cmd" reg add "$winebus_key" /v "DisableHidraw" /t REG_DWORD /d 1 /f
        "$wine_cmd" reg add "$winebus_key" /v "Map Controllers" /t REG_DWORD /d 1 /f
        "$wine_cmd" reg delete "$dll_overrides_key" /v "xinput1_3" /f || true
      else
        "$wine_cmd" reg add "$winebus_key" /v "Enable SDL" /t REG_DWORD /d 0 /f
        "$wine_cmd" reg add "$winebus_key" /v "DisableHidraw" /t REG_DWORD /d 0 /f
        "$wine_cmd" reg add "$winebus_key" /v "Map Controllers" /t REG_DWORD /d 0 /f
      fi

      echo "Applied MiniHost WineBus $mode settings to ''${WINEPREFIX:-$HOME/.wine}."
      echo "Restart the game or run: WINEPREFIX=\"''${WINEPREFIX:-$HOME/.wine}\" wineserver -k"
    '';
  };

  minihostWine = pkgs.writeShellApplication {
    name = "minihost-wine";
    runtimeInputs = [ pkgs.wineWow64Packages.stable ];
    text = ''
      set -euo pipefail

      export SDL_GAMECONTROLLERCONFIG="${minihostSdlMapping}"
      exec "''${WINE:-wine}" "$@"
    '';
  };

  protonDefault = pkgs.callPackage ../../../../pkgs/games/proton-default.nix { };
in
{
  options.software.apps.gaming.enable = lib.mkEnableOption "gaming tools and launchers";
  options.software.apps.gaming.lsfgVk.enable = lib.mkEnableOption "lsfg-vk frame generation layer";

  config = lib.mkIf cfg.enable {
    programs.steam = {
      enable = true;
      remotePlay.openFirewall = true;
      dedicatedServer.openFirewall = true;
      localNetworkGameTransfers.openFirewall = true;
      extraPackages = lib.optionals cfg.lsfgVk.enable [ pkgs.lsfg-vk ];
    };

    programs.gamescope = {
      enable = true;
      capSysNice = false; # gamescope's sandboxing is too aggressive for some games, e.g. steam
      package = pkgs.gamescope.overrideAttrs (_: {
        NIX_CFLAGS_COMPILE = [ "-fno-fast-math" ];
      });
    };

    programs.gpu-screen-recorder.enable = true;

    hardware.graphics = {
      enable = true;
      enable32Bit = true;
      # MangoHud's Vulkan layer must be on the host driver path (both bitnesses)
      # for pressure-vessel to import it into umu/Proton containers; it stays
      # dormant unless MANGOHUD=1. systemPackages alone doesn't reach the
      # in-container loader. GHWTDE is 32-bit, so the i686 layer is required.
      extraPackages = [ pkgs.mangohud ] ++ lib.optionals cfg.lsfgVk.enable [ pkgs.lsfg-vk ];
      extraPackages32 =
        [ pkgs.pkgsi686Linux.mangohud ]
        ++ lib.optionals cfg.lsfgVk.enable [ pkgs.pkgsi686Linux.lsfg-vk ];
    };

    services.udev = {
      packages = [ pkgs.game-devices-udev-rules ];
      extraRules = ''
        # Wine's raw HID path needs access to the MiniHost hidraw node.
        KERNEL=="hidraw*", ATTRS{idVendor}=="1209", ATTRS{idProduct}=="2882", GROUP="input", MODE="0660", TAG+="uaccess"
      '';
    };

    # MiniHost GH Guitar controller mapping
    environment.sessionVariables = {
      SDL_GAMECONTROLLERCONFIG = minihostSdlMapping;
    }
    // lib.optionalAttrs cfg.lsfgVk.enable {
      DISABLE_LSFG = "1";
    };

    environment.systemPackages =
      with pkgs;
      [
        mesa
        mesa-demos
        # Launchers
        heroic
        faugus-launcher
        (pkgs.bolt-launcher.override { jdk17 = pkgs.openjdk; })
        boilr
        (pkgs.callPackage ../../../../pkgs/yarc-launcher.nix { })

        # Mod / config tools
        protonplus
        prismlauncher
        gpu-screen-recorder
        minihostWineGuitarFix
        minihostWine
        protonDefault
        wineWow64Packages.stable
        winetricks

        # Performance
        gamemode
        mangohud
        vulkan-headers

        # Streaming
        moonlight-qt
      ]
      ++ lib.optionals cfg.lsfgVk.enable [
        lsfg-vk
        vulkan-tools
      ];
  };
}
