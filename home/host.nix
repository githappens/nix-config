# Minimal host profile — just GPG/YubiKey SSH for VM provisioning.
# No dev tools, no git signing, no shell aliases.
{ pkgs, ... }:
{
  imports = [
    ./gpg.nix
  ];

  home.username = "bence";
  home.homeDirectory = "/Users/bence";
  home.stateVersion = "25.11";

  programs.zsh = {
    enable = true;
    initExtra = ''
      # GPG-agent as SSH agent (YubiKey SSH for VM provisioning)
      export GPG_TTY=$(tty)
      export SSH_AUTH_SOCK=$(gpgconf --list-dirs agent-ssh-socket)
      gpgconf --launch gpg-agent
      gpg-connect-agent updatestartuptty /bye 2>/dev/null
    '';
  };
}
