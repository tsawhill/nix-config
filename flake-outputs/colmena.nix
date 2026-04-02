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

  # For hosts using nixpkgs-unstable (desktop, laptop)
  mkUnstableHost = tag: targetHost: modulePath: {
    deployment = {
      targetUser = "root";
      nixpkgs = import nixpkgs-unstable { localSystem = "x86_64-linux"; };
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
    _module.args = {
      home-manager-input = inputs.home-manager-unstable;
      nixvim-input = inputs.nixvim-unstable;
      sops-input = inputs.sops-nix-unstable;
      zen-input = inputs.zen-browser-unstable;
    };
    imports = [ modulePath ];
  };

in
{
  colmena = {
    meta = {
      nixpkgs = import nixpkgs-stable { localSystem = "x86_64-linux"; };
      specialArgs = sharedArgs;
    };

    # --- self (local deploy, no SSH) ---
    "build-nix" = mkHost "self" null "${self}/hosts/server-nix/LXCs/build.nix";

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
    "arrs-nix" = mkHost "weekly" "arrs-nix.lan" "${self}/hosts/server-nix/LXCs/arrs.nix";
    "socks5-vpn-eu-nix" =
      mkHost "weekly" "socks5-vpn-eu-nix.lan"
        "${self}/hosts/server-nix/LXCs/socks5-vpn-eu.nix";
    "acme-nix" = mkHost "weekly" "acme-nix.lan" "${self}/hosts/server-nix/LXCs/acme.nix";
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
      mkUnstableHost "weekly" "taylor-desktop-nix.lan"
        "${self}/hosts/taylor-desktop-nix";
    "taylor-laptop-nix" =
      mkUnstableHost "weekly" "taylor-laptop-nix.lan"
        "${self}/hosts/taylor-laptop-nix";
    # --- main server ---
    "server-nix" = mkHost "weekly" "server-nix.lan" "${self}/hosts/server-nix";
  };
}
