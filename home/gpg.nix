# YubiKey-aware GPG + gpg-agent with SSH support.
{ pkgs, ... }:
{
  programs.gpg = {
    enable = true;
    scdaemonSettings = {
      disable-ccid = "";
    };
  };

  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
    defaultCacheTtl = 600;
    maxCacheTtl = 7200;
    pinentry.package = pkgs.pinentry_mac;
  };
}
