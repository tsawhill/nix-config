{ inputs, self, ... }:
{
  imports = [
    inputs.home-manager-stable.nixosModules.default
  ];

  home-manager = {
    extraSpecialArgs = {
      inherit inputs self;
      nixvim-input = inputs.nixvim-stable;
    };

    users.root = {
      imports = [ "${self}/modules/home-manager/bundles/all.nix" ];
      home.stateVersion = "25.11";
    };

    users.taylor = {
      imports = [ "${self}/modules/home-manager/bundles/all.nix" ];
      home.stateVersion = "25.11";
    };

    backupFileExtension = "bak";
    useGlobalPkgs = true;
    useUserPackages = true;
  };
}
