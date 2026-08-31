{ inputs, self, ... }:
{
  imports = [ inputs.home-manager-stable.nixosModules.default ];

  home-manager = {
    users.root = {
      imports = [
        "${self}/modules/home-manager/bundles/server.nix"
      ];

      home.stateVersion = "26.05";
    };

    backupFileExtension = "bak";
    useGlobalPkgs = true;

    extraSpecialArgs = {
      inherit inputs;
      nixvim-input = inputs.nixvim-stable;
    };
  };
}
