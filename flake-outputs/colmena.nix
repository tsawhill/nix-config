inputs@{
  self,
  nixpkgs-stable,
  nixpkgs-unstable,
  ...
}:
let
  sharedArgs = {
    inherit inputs;
    self = self;
    home-manager-input = inputs.home-manager-stable;
    nixvim-input = inputs.nixvim-stable;
    sops-input = inputs.sops-nix-stable;
    nix-vscode-extensions-input = inputs.nix-vscode-extensions-stable;
  };

  # tag:       schedule tag used by timers (null = manual-only)
  # targetHost: SSH target, or null for local deployment (build-nix self-update)
  mkHost = tag: targetHost: modulePath: {
    deployment = {
      targetUser = "root";
    }
    // (
      if targetHost == null then
        {
          allowLocalDeployment = true;
          targetHost = null;
        }
      else
        { inherit targetHost; }
    )
    // (if tag != null then { tags = [ tag ]; } else { });
    imports = [ modulePath ];
  };

  unstablePkgs = import nixpkgs-unstable {
    localSystem = "x86_64-linux";
    config.allowUnfree = true;
  };
  piPkgs = import inputs.nixos-raspberrypi.inputs.nixpkgs { localSystem = "aarch64-linux"; };

  unstableArgs = sharedArgs // {
    home-manager-input = inputs.home-manager-unstable;
    nixvim-input = inputs.nixvim-unstable;
    sops-input = inputs.sops-nix-unstable;
    zen-input = inputs.zen-browser-unstable;
    nix-vscode-extensions-input = inputs.nix-vscode-extensions-unstable;
  };

  mkPiHost = tag: targetHost: {
    deployment = {
      targetUser = "root";
      inherit targetHost;
    }
    // (if tag != null then { tags = [ tag ]; } else { });
    _module.args = {
      nixvim-input = inputs.nixvim-stable;
      nixos-raspberrypi = inputs.nixos-raspberrypi;
    };
    imports = [
      {
        nixpkgs.hostPlatform = "aarch64-linux";
        imports = with inputs.nixos-raspberrypi.nixosModules; [
          trusted-nix-caches
          nixpkgs-rpi
          inputs.nixos-raspberrypi.lib.inject-overlays
          raspberry-pi-5.base
          raspberry-pi-5.page-size-16k
          raspberry-pi-5.display-vc4
          sd-image
        ];
      }
      "${self}/hosts/pi-backup-nix"
    ];
  };

  # For hosts using nixpkgs-unstable (desktop, laptop)
  mkUnstableHost = tag: targetHost: modulePath: {
    deployment = {
      targetUser = "root";
    }
    // (
      if targetHost == null then
        {
          allowLocalDeployment = true;
          targetHost = null;
        }
      else
        { inherit targetHost; }
    )
    // (if tag != null then { tags = [ tag ]; } else { });
    imports = [ modulePath ];
  };

in
{
  colmena = {
    meta = {
      nixpkgs = import nixpkgs-stable { localSystem = "x86_64-linux"; };
      specialArgs = sharedArgs;
      nodeNixpkgs = {
        "pi-backup-nix" = piPkgs;
        "taylor-desktop-nix" = unstablePkgs;
        "taylor-laptop-nix" = unstablePkgs;
      };
      nodeSpecialArgs = {
        "taylor-desktop-nix" = unstableArgs;
        "taylor-laptop-nix" = unstableArgs;
      };
    };

    # --- local deploy (no SSH, uses apply-local) ---
    "build-nix" = mkHost "daily" null "${self}/hosts/server-nix/LXCs/build.nix";
    # "router-nix" = mkHost null "router-nix.lan" "${self}/hosts/server-nix/LXCs/router.nix";

    # --- daily ---
    "local-nginx-nix" =
      mkHost "daily" "local-nginx-nix.lan"
        "${self}/hosts/server-nix/LXCs/local-nginx.nix";
    "remote-nginx-nix" = mkHost "daily" "remote-nginx-nix.lan" "${self}/hosts/remote-nginx-nix";

    # --- weekly ---
    "vaultwarden-nix" =
      mkHost "weekly" "vaultwarden-nix.lan"
        "${self}/hosts/server-nix/LXCs/vaultwarden.nix";
    "unbound-vpn-na-nix" =
      mkHost "weekly" "unbound-vpn-na-nix.lan"
        "${self}/hosts/server-nix/LXCs/unbound-vpn-na.nix";
    "adguard-nix" = mkHost "weekly" "adguard-nix.lan" "${self}/hosts/server-nix/LXCs/adguard.nix";
    "nextcloud-nix" = mkHost "weekly" "nextcloud-nix.lan" "${self}/hosts/server-nix/LXCs/nextcloud.nix";
    "jellyseerr-nix" =
      mkHost "weekly" "jellyseerr-nix.lan"
        "${self}/hosts/server-nix/LXCs/jellyseerr.nix";
    "jellyfin-nix" = mkHost "weekly" "jellyfin-nix.lan" "${self}/hosts/server-nix/LXCs/jellyfin.nix";
    "gotify-nix" = mkHost "weekly" "gotify-nix.lan" "${self}/hosts/server-nix/LXCs/gotify.nix";
    "llm-nix" = mkHost "weekly" "llm-nix.lan" "${self}/hosts/server-nix/LXCs/llm.nix";
    "searx-nix" = mkHost "weekly" "searx-nix.lan" "${self}/hosts/server-nix/LXCs/searx.nix";
    "arrs-nix" = mkHost "weekly" "arrs-nix.lan" "${self}/hosts/server-nix/LXCs/arrs.nix";
    "socks5-vpn-eu-nix" =
      mkHost "weekly" "socks5-vpn-eu-nix.lan"
        "${self}/hosts/server-nix/LXCs/socks5-vpn-eu.nix";
    "sunshine-nix" = mkHost "weekly" "sunshine-nix.lan" "${self}/hosts/server-nix/LXCs/sunshine.nix";

    # --- monthly ---
    "unifi-nix" = mkHost "monthly" "unifi-nix.lan" "${self}/hosts/server-nix/LXCs/unifi.nix";
    "samba-nix" = mkHost "monthly" "samba-nix.lan" "${self}/hosts/server-nix/LXCs/samba.nix";
    "immich-nix" = mkHost "monthly" "immich-nix.lan" "${self}/hosts/server-nix/LXCs/immich.nix";
    "pufferpanel-nix" =
      mkHost "monthly" "pufferpanel-nix.lan"
        "${self}/hosts/server-nix/LXCs/pufferpanel.nix";
    "deluge-nix" = mkHost "monthly" "deluge-nix.lan" "${self}/hosts/server-nix/LXCs/deluge.nix";
    "authentik-nix" =
      mkHost "monthly" "authentik-nix.lan"
        "${self}/hosts/server-nix/LXCs/authentik.nix";
    "romm-nix" = mkHost "monthly" "romm-nix.lan" "${self}/hosts/server-nix/LXCs/romm.nix";
    "syncthing-nix" =
      mkHost "monthly" "syncthing-nix.lan"
        "${self}/hosts/server-nix/LXCs/syncthing.nix";

    # --- personal machines (unstable, manual-only) ---
    "taylor-desktop-nix" =
      mkUnstableHost "daily" "taylor-desktop-nix.lan"
        "${self}/hosts/taylor-desktop-nix";
    "taylor-laptop-nix" =
      mkUnstableHost "daily" "taylor-laptop-nix.lan"
        "${self}/hosts/taylor-laptop-nix";
    # --- main server ---
    "server-nix" = mkHost "weekly" "server-nix.lan" "${self}/hosts/server-nix";

    # --- backup target ---
    "pi-backup-nix" = mkPiHost "weekly" "pi-backup-nix.lan";
  };
}
