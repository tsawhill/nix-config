inputs@{ self, nixpkgs-stable, ... }:
let
  networkTopology = import "${self}/modules/network/topology.nix";

  ociSpecialArgs = {
    inherit inputs;
    inherit networkTopology;
    self = self;
    nixvim-input = inputs.nixvim-stable;
  };
in
{
  nixosConfigurations = {

    ##########################################################################
    #                        remote-nginx-nix config                         #
    #  Superseded by oracle-1-nix. Kept until the OCI cutover is finished.    #
    ##########################################################################
    remote-nginx-nix = nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = ociSpecialArgs;
      modules = [ "${self}/hosts/remote-nginx-nix" ];
    };

    ##########################################################################
    #                          oracle-1-nix config                           #
    #                                                                        #
    #  OCI VM.Standard.A1.Flex (aarch64, 1 OCPU / 6 GB).                     #
    #                                                                        #
    #  Two targets on purpose:                                               #
    #    .#oracle-1-nix-bootstrap  -> first install via nixos-anywhere. No    #
    #                                 sops/wg/nginx, because the host's age   #
    #                                 key does not exist until it has booted  #
    #                                 once and generated an SSH host key.     #
    #    .#oracle-1-nix            -> full config. Reached with               #
    #                                 `deploy oracle-1-nix` after the age key #
    #                                 is enrolled in .sops.yaml.              #
    #                                                                        #
    #  Bootstrap first, enroll the host age key, then deploy the full target. #
    ##########################################################################
    oracle-1-nix-bootstrap = nixpkgs-stable.lib.nixosSystem {
      system = "aarch64-linux";
      specialArgs = ociSpecialArgs;
      modules = [ "${self}/hosts/oracle-1-nix/bootstrap.nix" ];
    };

    oracle-1-nix = nixpkgs-stable.lib.nixosSystem {
      system = "aarch64-linux";
      specialArgs = ociSpecialArgs // {
        home-manager-input = inputs.home-manager-stable;
        sops-input = inputs.sops-nix-stable;
      };
      modules = [ "${self}/hosts/oracle-1-nix" ];
    };
  };
}
