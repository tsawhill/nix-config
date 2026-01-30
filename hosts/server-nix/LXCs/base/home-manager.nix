{ inputs, self, ... }:
{
  imports = [ inputs.home-manager-stable.nixosModules.default ];

  home-manager.users.root = {
    imports = [
      "${self}/modules/home-manager/bundles/all.nix"
    ];

    home.stateVersion = "25.11";
  };

  home-manager.backupFileExtension = "bak";

  home-manager.extraSpecialArgs = {
    inherit inputs;
    nixvim-input = inputs.nixvim-stable;
  };
}
