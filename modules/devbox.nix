# Devbox VM — macOS Tahoe guest with nix-darwin + home-manager.
# Ephemeral (rollback mode), dev state persists via host-mapped drive.
{ pkgs, ... }:
{
  networking.hostName = "devbox";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  users.users.user = {
    home = "/Users/user";
    shell = "/bin/zsh";
  };

  # Home Manager — declarative user profile
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users."user" = import ../home;

  environment.systemPackages = with pkgs; [
    gnupg
    vim
    curl
    htop
  ];

  system.stateVersion = 5;
}
