# Git identity and GPG commit/tag signing.
# Replaces the standalone set-git-signing-config.sh script.
{ ... }:
{
  programs.git = {
    enable = true;

    signing = {
      key = "3BEF0F1F86B63AE0";
      signByDefault = true;
    };

    settings = {
      user = {
        name = "Bence Kovács";
        email = "23636204+githappens@users.noreply.github.com";
      };
      gpg.program = "gpg";
      tag.gpgSign = true;
    };
  };
}
