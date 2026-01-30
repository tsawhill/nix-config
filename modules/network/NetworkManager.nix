{
  # Enable networking
  networking.networkmanager.enable = true;

  # Define users dynamically
  users.users =
    let
      nmUsers = [ "taylor" ];
    in
    builtins.listToAttrs (
      map (name: {
        name = name;
        value = {
          extraGroups = [ "networkmanager" ];
          isNormalUser = true; # Usually required for non-root users
        };
      }) nmUsers
    );
}
