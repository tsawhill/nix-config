{
  inputs,
  self,
  home-manager-input,
  nixvim-input,
  ...
}:
{
  imports = [
    home-manager-input.nixosModules.default
  ];

  home-manager = {
    extraSpecialArgs = {
      inherit
        inputs
        self
        home-manager-input
        nixvim-input
        ;
    };

    users.root = {
      imports = [ "${self}/modules/home-manager/bundles/all.nix" ];
      home.stateVersion = "26.05";
      my.nixvim.full = true;
    };

    users.taylor = {
      imports = [ "${self}/modules/home-manager/bundles/all.nix" ];
      home.stateVersion = "26.05";
      my.nixvim.full = true;
    };

    backupFileExtension = "bak";
    useGlobalPkgs = true;
    useUserPackages = true;
  };
}
