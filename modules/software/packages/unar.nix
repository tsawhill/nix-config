{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [ unar ];
}
