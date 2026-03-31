# Parallels guest integration for NixOS VMs on Apple Silicon.
# Provides display integration, clipboard sharing, and shared folders.
{ config, pkgs, ... }: {
  hardware.parallels = {
    enable = true;
    autoMountShared = true; # shared folders at /mnt/psf/
  };

  # EFI boot (required for Parallels on Apple Silicon)
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # If prl-tools fail to build against the current kernel, uncomment:
  # boot.kernelPackages = pkgs.linuxPackages_6_6;
}
