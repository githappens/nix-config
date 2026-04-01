# Mullvad Browser kiosk VM.
# WireGuard full tunnel to Mullvad VPN, Mullvad Browser in sway (minimal Wayland).
# Mullvad Browser runs in a floating window at its default letterboxed size
# to avoid screen-size fingerprinting.
{ config, pkgs, lib, ... }:
let
  wgConf = "/etc/mullvad-wg/wg0.conf";

  swayConfig = pkgs.writeText "sway-config" ''
    # Minimal sway config for Mullvad Browser kiosk
    # Use virtio_gpu output
    output Virtual-1 resolution 1920x1080

    # All windows float by default — lets Mullvad Browser use its
    # built-in letterboxing for fingerprint resistance.
    for_window [app_id=".*"] floating enable

    # Dark background
    output * bg #1a1a2e solid_color

    # Cursor theme
    seat seat0 xcursor_theme Adwaita 24

    # Launch Mullvad Browser; exit sway when it closes
    exec mullvad-browser; swaymsg exit
  '';

  sway-kiosk = pkgs.writeShellScript "sway-kiosk" ''
    export XDG_SESSION_TYPE=wayland
    export WLR_NO_HARDWARE_CURSORS=1
    export XCURSOR_THEME=Adwaita
    export XCURSOR_SIZE=24
    export XCURSOR_PATH=/run/current-system/sw/share/icons
    export MOZ_ENABLE_WAYLAND=1
    exec ${pkgs.sway}/bin/sway --config ${swayConfig}
  '';
in {
  networking.hostName = "mullvad-vm";

  # ── WireGuard full tunnel ───────────────────────────────────────
  networking.wg-quick.interfaces.wg0 = {
    configFile = wgConf;
    autostart = true;
  };

  # The WireGuard config is deployed via nixos-anywhere --extra-files,
  # not through the Nix store (keeps secrets out of the world-readable store).
  # See manage-mullvad-vm.sh for the copy step.

  # ── DNS ─────────────────────────────────────────────────────────
  networking.nameservers = [ "10.64.0.1" ];

  # ── Sway (minimal Wayland compositor) ──────────────────────────
  # Sway instead of Cage so Mullvad Browser can use its default
  # letterboxed window size for fingerprint resistance.
  programs.sway.enable = true;

  # Auto-login and launch sway on tty1
  services.getty.autologinUser = "user";
  environment.loginShellInit = ''
    if [ "$(tty)" = "/dev/tty1" ] && [ -z "$WAYLAND_DISPLAY" ]; then
      exec ${sway-kiosk}
    fi
  '';

  # ── Auto-resize display ────────────────────────────────────────
  # Parallels updates the first mode in /sys/class/drm/card1-Virtual-1/modes
  # when the host window is resized. This service polls for changes and
  # applies them via wlr-randr. The browser stays at its letterboxed size.
  systemd.services.display-autoresize = {
    description = "Auto-resize sway display to match Parallels window";
    wantedBy = [ "multi-user.target" ];
    after = [ "getty@tty1.service" ];
    serviceConfig = {
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 5";
      ExecStart = let script = pkgs.writeShellScript "display-autoresize" ''
        export XDG_RUNTIME_DIR=/run/user/1000
        # Find the active wayland socket
        for s in wayland-0 wayland-1 wayland-2; do
          if [ -S "$XDG_RUNTIME_DIR/$s" ]; then
            export WAYLAND_DISPLAY="$s"
            break
          fi
        done
        MODES_FILE="/sys/class/drm/card1-Virtual-1/modes"
        LAST=""
        while true; do
          MODE=$(head -1 "$MODES_FILE" 2>/dev/null)
          if [ -n "$MODE" ] && [ "$MODE" != "$LAST" ]; then
            ${pkgs.wlr-randr}/bin/wlr-randr --output Virtual-1 --custom-mode "$MODE"
            LAST="$MODE"
          fi
          sleep 1
        done
      '';
      in "${script}";
      User = "user";
      Restart = "always";
      RestartSec = 3;
    };
  };

  # ── User ────────────────────────────────────────────────────────
  users.users.user = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialPassword = "changeme";
  };

  # Fix ownership of SSH authorized_keys deployed via --extra-files
  system.activationScripts.fix-ssh-keys = ''
    if [ -d /home/user/.ssh ]; then
      chown -R user:users /home/user/.ssh
    fi
  '';

  # Passwordless sudo for remote updates via SSH key
  security.sudo.extraRules = [{
    users = [ "user" ];
    commands = [
      { command = "ALL"; options = [ "NOPASSWD" ]; }
    ];
  }];

  # ── Firewall ────────────────────────────────────────────────────
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
    allowedUDPPorts = [ ];
    trustedInterfaces = [ "wg0" ];
  };

  # ── SSH (key-only, for remote nixos-rebuild) ─────────────────────
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  # ── Minimal system ─────────────────────────────────────────────
  time.timeZone = "Europe/London";
  i18n.defaultLocale = "en_US.UTF-8";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  environment.systemPackages = with pkgs; [
    mullvad-browser
    adwaita-icon-theme
    wlr-randr
    vim
    htop
    curl
  ];

  system.stateVersion = "25.11";
}
