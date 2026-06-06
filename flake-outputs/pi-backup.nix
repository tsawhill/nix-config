inputs@{ self, ... }:
let
  networkTopology = import "${self}/modules/network/topology.nix";
in
{
  nixosConfigurations = {

    ##########################################################################
    #                          pi-backup-nix config                          #
    ##########################################################################
    pi-backup-nix = inputs.nixos-raspberrypi.lib.nixosSystem {
      specialArgs = {
        inherit inputs;
        inherit networkTopology;
        self = self;
        nixvim-input = inputs.nixvim-stable;
        nixos-raspberrypi = inputs.nixos-raspberrypi;
      };
      modules = [
        {
          imports = with inputs.nixos-raspberrypi.nixosModules; [
            raspberry-pi-5.base
            raspberry-pi-5.page-size-16k
            raspberry-pi-5.display-vc4
            sd-image
          ];
        }
        "${self}/hosts/pi-backup-nix"
      ];
    };
  };
}
