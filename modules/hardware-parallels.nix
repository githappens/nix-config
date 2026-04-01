# Parallels guest integration for NixOS VMs on Apple Silicon.
# Provides display integration, clipboard sharing, and shared folders.
{ config, pkgs, lib, ... }: {
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "prl-tools"
  ];

  hardware.parallels = {
    enable = true;
  };

  # EFI boot (required for Parallels on Apple Silicon)
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.consoleMode = "auto";
  boot.loader.timeout = 3;
  boot.loader.efi.canTouchEfiVariables = true;

  # nixos-25.11 defaults to kernel 6.17, but prl-tools only supports up to 6.13.
  # Pin to 6.12 LTS for Parallels guest integration (display resize, clipboard).
  boot.kernelPackages = pkgs.linuxPackages_6_12;
}
