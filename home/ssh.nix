# SSH client config — host entries only, no private keys.
# Private keys are manually provisioned into ~/.ssh/ before snapshotting.
# Local overrides go in ~/.ssh/config.local (included automatically).
{ ... }:
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    includes = [ "config.local" ];

    matchBlocks = {
      "opnsense" = {
        hostname = "opnsense.itthon";
        user = "root";
      };

      "github.com" = {
        user = "git";
        identitiesOnly = true;
        identityFile = "~/.ssh/id_yubikey.pub";
        extraOptions = {
          IdentityAgent = "~/.gnupg/S.gpg-agent.ssh";
        };
      };

      "github.com-BD-Bence" = {
        hostname = "github.com";
        user = "git";
        identityFile = "~/.ssh/id_rsa_BD";
        identitiesOnly = true;
      };

      "nova" = {
        user = "ubuntu";
      };

      "nassie nassie.production" = {
        hostname = "nassie.production";
        user = "benceadmin";
        port = 42;
        identityFile = "~/.ssh/id_yubikey.pub";
      };
    };
  };
}
