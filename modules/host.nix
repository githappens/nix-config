# Locked-down host — minimal nix-darwin config.
# Only purpose: GPG/YubiKey SSH for provisioning VMs.
{ ... }:
{
  networking.hostName = "m5pro";

  nix.enable = false;  # Nix is managed by Determinate installer

  users.users.bence = {
    home = "/Users/bence";
    shell = "/bin/zsh";
  };

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users."bence" = import ../home/host.nix;

  system.stateVersion = 5;
}
