# Nix Config

NixOS VM and host configurations.

## Current targets

- **mullvad-vm** — Mullvad Browser kiosk over WireGuard full tunnel VPN (Mullvad Browser 16.0a4 alpha, aarch64)

## Architecture

The mullvad-vm is a minimal NixOS VM running inside Parallels on Apple Silicon. Sway (a minimal Wayland compositor) launches Mullvad Browser in a floating window at its default letterboxed size for fingerprint resistance. All traffic goes through a WireGuard full tunnel to Mullvad VPN. DNS resolves through Mullvad's DNS server (`10.64.0.1`) inside the tunnel.

Display auto-resize is handled by a custom systemd service that polls the `virtio_gpu` mode list and applies changes via `wlr-randr` — no Parallels Tools kernel modules required.

```
Host (macOS)
└── Parallels (shared/NAT networking)
    └── mullvad-vm (NixOS, aarch64-linux)
        ├── WireGuard full tunnel → Mullvad VPN
        ├── sway (minimal Wayland compositor)
        └── Mullvad Browser (floating, letterboxed)
```

## Setup guide

### Prerequisites

- [Nix](https://install.determinate.systems/nix) installed on the host
- [Parallels Desktop](https://www.parallels.com/) installed
- NixOS minimal ISO (aarch64) downloaded to `~/ISOs/`
- A Mullvad VPN account with a WireGuard config

### Step 1: Download the NixOS minimal ISO

```bash
mkdir -p ~/ISOs
curl -L -o ~/ISOs/nixos-minimal-aarch64-linux.iso \
  https://channels.nixos.org/nixos-25.11/latest-nixos-minimal-aarch64-linux.iso
```

### Step 2: Set up your Mullvad WireGuard config

Get a WireGuard config from https://mullvad.net/en/account/wireguard-config (pick a server, generate a key). Then:

```bash
cp secrets/mullvad-wg.conf.example secrets/mullvad-wg.conf
```

Paste your Mullvad config into `secrets/mullvad-wg.conf`. This file is gitignored and never leaves your machine.

### Step 3: Create and install

```bash
./scripts/manage-mullvad-vm.sh create
```

This will:
1. Create a Parallels VM (4 CPU, 8GB RAM, 15GB disk)
2. Apply privacy hardening (isolate VM, disable camera/printer/clipboard/cloud/app sharing)
3. Boot the NixOS installer ISO
4. Auto-detect the VM IP and install NixOS via nixos-anywhere
5. Generate an SSH deploy key (stored in `secrets/vm-ssh-key`, gitignored)
6. Disconnect the ISO, create a clean snapshot, and enable rollback mode

The only manual steps are setting `sudo passwd` in the VM console when prompted (NixOS installer requires this before SSH access), and verifying camera/microphone are off in the GUI afterwards. If the disk isn't `/dev/sda`, update `disko/mullvad-vm.nix` before running create.

### Step 4: Verify

The VM should boot into sway with Mullvad Browser in a floating window. Navigate to https://mullvad.net/en/check — it should show your Mullvad exit IP, not your real IP.

Login credentials: `user` / `changeme`

## Ephemeral mode

The VM runs in Parallels **Rollback Mode** — every shutdown reverts it to the last clean snapshot. Browser history, downloads, cookies, and any other state are wiped automatically. This is by design for privacy.

Rollback Mode is enabled automatically via `--undo-disks discard` after the initial install. The `update` command creates a new clean snapshot after each update.

## Updating

```bash
./scripts/manage-mullvad-vm.sh update
```

This will:
1. Update `flake.lock` to the latest nixpkgs
2. Check for a new Mullvad Browser alpha and update the hash in `pkgs/mullvad-browser.nix`
3. Stop the VM, disable rollback mode (`--undo-disks off`), deploy via `nixos-rebuild switch`
4. Create a new clean snapshot and re-enable rollback mode (`--undo-disks discard`)

## Day-to-day usage

```bash
prlctl start mullvad-vm        # Start the VM
prlctl stop mullvad-vm         # Stop the VM
ssh -i secrets/vm-ssh-key user@<vm-ip>  # SSH in for troubleshooting
```

## Troubleshooting

**WireGuard tunnel not coming up:** SSH in, check `sudo systemctl status wg-quick-wg0`. Verify `secrets/mullvad-wg.conf` is correct.

**Sway doesn't start / black screen:** SSH in, check `journalctl -u getty@tty1`. Verify the login shell init is launching sway.

**Display not resizing:** Check `systemctl status display-autoresize`. The service polls `/sys/class/drm/card1-Virtual-1/modes` and applies changes via `wlr-randr`.

**No cursor:** The VM uses software cursors (`WLR_NO_HARDWARE_CURSORS=1`). If the cursor disappears, reboot the VM.

**Wrong disk device:** If `nixos-anywhere` fails during partitioning, boot the ISO again, run `lsblk`, and update `device` in `disko/mullvad-vm.nix`.
