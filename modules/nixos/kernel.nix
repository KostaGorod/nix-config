{ pkgs, ... }:
{
  # Use latest kernel to get CVE-2026-31431 (Copy Fail) and other security patches
  boot.kernelPackages = pkgs.linuxPackages_latest;
}
