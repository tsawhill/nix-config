{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [ linux-firmware ];
}
