{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [ iputils ];
}
