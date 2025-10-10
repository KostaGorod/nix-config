{ pkgs, lib, ... }:
{
  environment.systemPackages = with pkgs; [
    moonlight-qt
  ];
}