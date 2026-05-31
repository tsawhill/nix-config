{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.software.apps.gaming;

  minihostWineGuitarFix = pkgs.writeShellApplication {
    name = "minihost-wine-guitar-fix";
    runtimeInputs = [ pkgs.wineWow64Packages.stable ];
    text = ''
      set -euo pipefail

      usage() {
        cat <<'EOF'
      Usage:
        minihost-wine-guitar-fix [--raw|--mapped-gamepad] [path/to/wine-prefix]

      Applies WineBus controller settings for the RetroCultMods MiniHost GH Guitar.
      The default --raw mode keeps Wine on the raw HID/DirectInput path and disables
      Wine's SDL controller-to-XInput gamepad mapping.
      Set WINE=/path/to/wine first if you want to use a specific Wine/Proton wine binary.
      EOF
      }

      if [ "''${1:-}" = "--help" ] || [ "''${1:-}" = "-h" ]; then
        usage
        exit 0
      fi

      mode="raw"
      case "''${1:-}" in
        --raw)
          mode="raw"
          shift
          ;;
        --mapped-gamepad)
          mode="mapped-gamepad"
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

      if [ "$mode" = "raw" ]; then
        "$wine_cmd" reg add "$winebus_key" /v "Enable SDL" /t REG_DWORD /d 0 /f
        "$wine_cmd" reg add "$winebus_key" /v "DisableHidraw" /t REG_DWORD /d 0 /f
        "$wine_cmd" reg add "$winebus_key" /v "Map Controllers" /t REG_DWORD /d 0 /f
      else
        "$wine_cmd" reg add "$winebus_key" /v "Enable SDL" /t REG_DWORD /d 1 /f
        "$wine_cmd" reg add "$winebus_key" /v "DisableHidraw" /t REG_DWORD /d 1 /f
        "$wine_cmd" reg add "$winebus_key" /v "Map Controllers" /t REG_DWORD /d 1 /f
      fi

      echo "Applied MiniHost WineBus $mode settings to ''${WINEPREFIX:-$HOME/.wine}."
      echo "Restart the game or run: WINEPREFIX=\"''${WINEPREFIX:-$HOME/.wine}\" wineserver -k"
    '';
  };
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

    services.udev = {
      packages = [ pkgs.game-devices-udev-rules ];
      extraRules = ''
        # Wine's raw HID path needs access to the MiniHost hidraw node.
        KERNEL=="hidraw*", ATTRS{idVendor}=="1209", ATTRS{idProduct}=="2882", GROUP="input", MODE="0660", TAG+="uaccess"
      '';
    };

    # MiniHost GH Guitar controller mapping
    environment.sessionVariables = {
      SDL_GAMECONTROLLERCONFIG = "03000000091200008228000001010000,MiniHost GH Guitar,platform:Linux,a:b0,b:b1,x:b3,y:b4,leftshoulder:b6,back:b10,start:b11,dpup:h0.1,dpdown:h0.4,leftx:a0,righty:a2";
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
