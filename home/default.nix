# Devbox VM user profile — ties together all dotfile modules.
{ ... }:
{
  imports = [
    ./gpg.nix
    ./ssh.nix
    ./git.nix
    ./shell.nix
  ];

  home.username = "user";
  home.homeDirectory = "/Users/user";
  home.stateVersion = "25.11";

  home.file."scripts/.scripttemplate" = {
    source = ./scripttemplate;
    executable = true;
  };
}
