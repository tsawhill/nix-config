{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [ dnsutils ];
}
