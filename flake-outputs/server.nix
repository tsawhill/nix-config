inputs@{ self, nixpkgs-stable, ... }:
{
  nixosConfigurations = {

    ##########################################################################
    #                            server-nix config                           #
    ##########################################################################
    server-nix = nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        self = self;
        nixvim-input = inputs.nixvim-stable;
      };
      modules = [ "${self}/hosts/server-nix" ];
    };

    ##########################################################################
    #                           authentik-nix config                         #
    ##########################################################################
    authentik-nix = nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        self = self;
        nixvim-input = inputs.nixvim-stable;
      };
      modules = [ "${self}/hosts/server-nix/LXCs/authentik.nix" ];
    };

    ##########################################################################
    #                             unifi-nix config                           #
    ##########################################################################
    unifi-nix = nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        self = self;
        nixvim-input = inputs.nixvim-stable;
      };
      modules = [ "${self}/hosts/server-nix/LXCs/unifi.nix" ];
    };

    ##########################################################################
    #                            samba-nix config                            #
    ##########################################################################
    samba-nix = nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        self = self;
        nixvim-input = inputs.nixvim-stable;
      };
      modules = [ "${self}/hosts/server-nix/LXCs/samba.nix" ];
    };

    ##########################################################################
    #                          syncthing-nix config                          #
    ##########################################################################
    syncthing-nix = nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        self = self;
        nixvim-input = inputs.nixvim-stable;
      };
      modules = [ "${self}/hosts/server-nix/LXCs/syncthing.nix" ];
    };

    ##########################################################################
    #                        unbound-vpn-na-nix config                       #
    ##########################################################################
    unbound-vpn-na-nix = nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        self = self;
        nixvim-input = inputs.nixvim-stable;
      };
      modules = [ "${self}/hosts/server-nix/LXCs/unbound-vpn-na.nix" ];
    };

    ##########################################################################
    #                           adguard-nix config                           #
    ##########################################################################
    adguard-nix = nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        self = self;
        nixvim-input = inputs.nixvim-stable;
      };
      modules = [ "${self}/hosts/server-nix/LXCs/adguard.nix" ];
    };

    ##########################################################################
    #                         pufferpanel-nix config                         #
    ##########################################################################
    pufferpanel-nix = nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        self = self;
        nixvim-input = inputs.nixvim-stable;
      };
      modules = [ "${self}/hosts/server-nix/LXCs/pufferpanel.nix" ];
    };

    ##########################################################################
    #                           sunshine-nix config                          #
    ##########################################################################
    sunshine-nix = nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        self = self;
        nixvim-input = inputs.nixvim-stable;
      };
      modules = [ "${self}/hosts/server-nix/LXCs/sunshine.nix" ];
    };

    ##########################################################################
    #                            socks5-vpn-eu-nix config                           #
    ##########################################################################
    socks5-vpn-eu-nix = nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        self = self;
        nixvim-input = inputs.nixvim-stable;
      };
      modules = [ "${self}/hosts/server-nix/LXCs/socks5-vpn-eu.nix" ];
    };

    ##########################################################################
    #                            build-nix config                            #
    ##########################################################################
    build-nix = nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        self = self;
        nixvim-input = inputs.nixvim-stable;
      };
      modules = [ "${self}/hosts/server-nix/LXCs/build.nix" ];
    };

    ##########################################################################
    #                            acme-nix config                             #
    ##########################################################################
    acme-nix = nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        self = self;
        nixvim-input = inputs.nixvim-stable;
      };
      modules = [ "${self}/hosts/server-nix/LXCs/acme.nix" ];
    };

    ##########################################################################
    #                        local-nginx-nix config                          #
    ##########################################################################
    local-nginx-nix = nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        self = self;
      };
      modules = [ "${self}/hosts/server-nix/LXCs/local-nginx.nix" ];
    };

    ##########################################################################
    #                         vaultwarden-nix config                         #
    ##########################################################################
    vaultwarden-nix = nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        self = self;
        nixvim-input = inputs.nixvim-stable;
      };
      modules = [ "${self}/hosts/server-nix/LXCs/vaultwarden.nix" ];
    };

    ##########################################################################
    #                          nextcloud-nix config                          #
    ##########################################################################
    nextcloud-nix = nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        self = self;
        nixvim-input = inputs.nixvim-stable;
      };
      modules = [ "${self}/hosts/server-nix/LXCs/nextcloud.nix" ];
    };

    ##########################################################################
    #                           gotify-nix config                            #
    ##########################################################################
    gotify-nix = nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        self = self;
        nixvim-input = inputs.nixvim-stable;
      };
      modules = [ "${self}/hosts/server-nix/LXCs/gotify.nix" ];
    };

    ##########################################################################
    #                             llm-nix config                             #
    ##########################################################################
    llm-nix = nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        self = self;
        nixvim-input = inputs.nixvim-stable;
      };
      modules = [ "${self}/hosts/server-nix/LXCs/llm.nix" ];
    };

    ##########################################################################
    #                          immich-nix config                           #
    ##########################################################################
    immich-nix = nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        self = self;
        nixvim-input = inputs.nixvim-stable;
      };
      modules = [ "${self}/hosts/server-nix/LXCs/immich.nix" ];
    };

    ##########################################################################
    #                          jellyfin-nix config                           #
    ##########################################################################
    jellyfin-nix = nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        self = self;
        nixvim-input = inputs.nixvim-stable;
      };
      modules = [ "${self}/hosts/server-nix/LXCs/jellyfin.nix" ];
    };

    ##########################################################################
    #                            romm-nix config                             #
    ##########################################################################
    romm-nix = nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        self = self;
        nixvim-input = inputs.nixvim-stable;
      };
      modules = [ "${self}/hosts/server-nix/LXCs/romm.nix" ];
    };

    ##########################################################################
    #                         jellyseerr-nix config                          #
    ##########################################################################
    jellyseerr-nix = nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        self = self;
        nixvim-input = inputs.nixvim-stable;
      };
      modules = [ "${self}/hosts/server-nix/LXCs/jellyseerr.nix" ];
    };

    ##########################################################################
    #                            arrs-nix config                             #
    ##########################################################################
    arrs-nix = nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        self = self;
        nixvim-input = inputs.nixvim-stable;
      };
      modules = [ "${self}/hosts/server-nix/LXCs/arrs.nix" ];
    };

    ##########################################################################
    #                           deluge-nix config                            #
    ##########################################################################
    deluge-nix = nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        self = self;
        nixvim-input = inputs.nixvim-stable;
      };
      modules = [ "${self}/hosts/server-nix/LXCs/deluge.nix" ];
    };

  };
}
