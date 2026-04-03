# Devbox VM — macOS Tahoe guest with nix-darwin + home-manager.
# Ephemeral (rollback mode), dev state persists via host-mapped drive.
{ pkgs, ... }:
{
  networking.hostName = "devbox";

  nix.enable = false;  # Nix is managed by Determinate installer

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

  # ── SSH (key-only) ──────────────────────────────────────────────
  environment.etc."ssh/sshd_config.d/100-nix.conf".text = ''
    PasswordAuthentication no
    KbdInteractiveAuthentication no
  '';

  # ── System defaults ────────────────────────────────────────────
  system.defaults.NSGlobalDomain.AppleShowAllExtensions = true;
  system.defaults.NSGlobalDomain.AppleShowAllFiles = true;
  system.defaults.NSGlobalDomain.NSDocumentSaveNewDocumentsToCloud = false;
  system.defaults.dock.autohide = true;
  system.defaults.dock.show-recents = false;
  system.defaults.finder.AppleShowAllExtensions = true;
  system.defaults.finder.FXPreferredViewStyle = "clmv";
  system.defaults.trackpad.Clicking = true;

  system.stateVersion = 5;
}
