{
  self,
  ...
}:

let
  # Leave false for the factory run. After the factory adds this host's age
  # recipient: add the mtls-ca.yaml rule to .sops.yaml, run `mtls-ca init` on
  # build-nix, then flip this.
  caEnabled = true;
in
{
  imports = [
    ./base
    "${self}/modules/software/services/mtls-ca.nix"
  ];

  networking.hostName = "ca-nix";

  # No web UI or daemon: build-nix's `mtls-ca` tool signs over SSH as the mtls-ca user.
  my.services.mtlsCa.enable = true;
  my.secrets.mtls-ca.enable = caEnabled;
}
