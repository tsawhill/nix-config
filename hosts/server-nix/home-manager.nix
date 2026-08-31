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
      imports = [ "${self}/modules/home-manager/bundles/server.nix" ];
      home.stateVersion = "26.05";
    };

    users.taylor = {
      imports = [ "${self}/modules/home-manager/bundles/server.nix" ];
      home.stateVersion = "26.05";
    };

    backupFileExtension = "bak";
    useGlobalPkgs = true;
    useUserPackages = true;
  };
}
