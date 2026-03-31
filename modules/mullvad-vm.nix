# Mullvad Browser kiosk VM.
# WireGuard full tunnel to Mullvad VPN, Mullvad Browser in cage (Wayland kiosk).
# No desktop environment, no shared folders needed.
{ config, pkgs, lib, ... }:
let
  # Parse the WireGuard config from the secrets file.
  # Expected format: standard wg-quick INI (see secrets/mullvad-wg.conf.example).
  wgConf = "/etc/mullvad-wg/wg0.conf";
in {
  networking.hostName = "mullvad-vm";

  # ── WireGuard full tunnel ───────────────────────────────────────
  # Use wg-quick with the config file directly — avoids parsing
  # individual fields in Nix and lets you paste Mullvad's config as-is.
  networking.wg-quick.interfaces.wg0 = {
    configFile = wgConf;
    autostart = true;
  };

  # Deploy the secret WireGuard config at build time.
  # The file is read from secrets/mullvad-wg.conf (gitignored).
  environment.etc."mullvad-wg/wg0.conf" = {
    source = ../secrets/mullvad-wg.conf;
    mode = "0600";
  };

  # ── DNS ─────────────────────────────────────────────────────────
  # Force Mullvad DNS through the tunnel. The wg-quick DNS directive
  # handles this at runtime, but we also set it here as a fallback.
  networking.nameservers = [ "10.64.0.1" ];

  # ── Mullvad Browser (cage kiosk) ───────────────────────────────
  # Cage: Wayland kiosk compositor — runs one app fullscreen, nothing else.
  services.cage = {
    enable = true;
    user = "user";
    program = "${pkgs.mullvad-browser}/bin/mullvad-browser";
  };

  # ── User ────────────────────────────────────────────────────────
  users.users.user = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialPassword = "changeme";
  };

  # ── Firewall ────────────────────────────────────────────────────
  # Allow WireGuard UDP out, then let the tunnel carry everything.
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ ];
    allowedUDPPorts = [ ];
    # wg-quick manages the routing table; the firewall just needs
    # to not block the tunnel establishment.
    trustedInterfaces = [ "wg0" ];
  };

  # ── Minimal system ─────────────────────────────────────────────
  time.timeZone = "Europe/London";
  i18n.defaultLocale = "en_US.UTF-8";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  environment.systemPackages = with pkgs; [
    mullvad-browser
    vim
    htop
    curl
  ];

  system.stateVersion = "25.05";
}
