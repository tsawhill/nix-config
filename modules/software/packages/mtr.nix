{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [ mtr ];
}
