{ lib, ... }:
{
  # OCI hands out the VNIC address over DHCP; the public IP is NAT'd to it.
  networking.useDHCP = lib.mkDefault true;
  networking.networkmanager.enable = true;
  networking.domain = "";

  # WireGuard replies leave via wg-remote while arriving on the OCI VNIC.
  networking.firewall.checkReversePath = "loose";
}
