# Nix Config

NixOS VM and host configurations.

## Current targets

- **mullvad-vm** — Mullvad Browser kiosk over WireGuard full tunnel VPN (Mullvad Browser 16.0a4 alpha, aarch64)

## Architecture

The mullvad-vm is a minimal NixOS VM running inside Parallels on Apple Silicon. It has no desktop environment — just cage (a Wayland kiosk compositor) launching Mullvad Browser fullscreen. All traffic goes through a WireGuard full tunnel to Mullvad VPN. DNS resolves through Mullvad's DNS server (`10.64.0.1`) inside the tunnel.

Display auto-resize is handled by a custom systemd service that polls the `virtio_gpu` mode list and applies changes via `wlr-randr` — no Parallels Tools kernel modules required.

```
Host (macOS)
└── Parallels (shared/NAT networking)
    └── mullvad-vm (NixOS, aarch64-linux)
        ├── WireGuard full tunnel → Mullvad VPN
        ├── cage (Wayland kiosk)
        └── Mullvad Browser (fullscreen)
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

### Step 3: Create the Parallels VM

```bash
./scripts/manage-mullvad-vm.sh create
```

This creates a Parallels VM (2 CPU, 2GB RAM, 15GB disk) and attaches the NixOS ISO.

### Step 4: Boot the ISO and prepare for install

```bash
prlctl start mullvad-vm
```

Once the NixOS installer boots to a shell:

```bash
# Set a root password (needed for SSH from the host)
passwd

# Find the VM's IP address
ip addr show enp0s5
```

### Step 5: Verify the disk device name

Still inside the VM console:

```bash
lsblk
```

If the 15GB disk is `/dev/sda`, you're good (that's what the disko config expects). If it's something else (e.g., `/dev/vda`), update the `device` field in `disko/mullvad-vm.nix` before proceeding.

### Step 6: Install NixOS

From the host terminal:

```bash
./scripts/manage-mullvad-vm.sh install <vm-ip>
```

This runs `nixos-anywhere` which partitions the disk, installs NixOS, and deploys the WireGuard secret. Takes ~5-10 minutes on first install.

### Step 7: Post-install

After the VM reboots, disconnect the ISO so it boots from disk:

```bash
prlctl set mullvad-vm --device-set cdrom0 --disconnect
prlctl restart mullvad-vm
```

### Step 8: Verify

The VM should boot into Mullvad Browser fullscreen. Navigate to https://mullvad.net/en/check — it should show your Mullvad exit IP, not your real IP.

Login credentials: `user` / `changeme`

## Updating

To update both NixOS (flake inputs) and Mullvad Browser to the latest versions:

```bash
./scripts/manage-mullvad-vm.sh update <vm-ip>
```

Or let the script auto-detect the IP (requires the VM to be running):

```bash
./scripts/manage-mullvad-vm.sh update
```

You can also set `MULLVAD_VM_IP` in your environment to skip passing the IP each time.

This will:
1. Update `flake.lock` to the latest nixpkgs
2. Check for a new Mullvad Browser alpha and update the hash in `pkgs/mullvad-browser.nix`
3. Rsync the config to the VM and run `nixos-rebuild switch`

## Day-to-day usage

```bash
prlctl start mullvad-vm        # Start the VM
prlctl stop mullvad-vm         # Stop the VM
ssh user@<vm-ip>               # SSH in for troubleshooting
```

## Troubleshooting

**WireGuard tunnel not coming up:** SSH in, check `sudo systemctl status wg-quick-wg0`. Verify `secrets/mullvad-wg.conf` is correct.

**Cage doesn't start / black screen:** SSH in, check `journalctl -u cage-tty1`. May need to verify Parallels GPU acceleration is working.

**Display not resizing:** Check `systemctl status display-autoresize`. The service polls `/sys/class/drm/card1-Virtual-1/modes` and applies changes via `wlr-randr`.

**No cursor:** The VM uses software cursors (`WLR_NO_HARDWARE_CURSORS=1`). If the cursor disappears, restart the cage service: `sudo systemctl restart cage-tty1`.

**Wrong disk device:** If `nixos-anywhere` fails during partitioning, boot the ISO again, run `lsblk`, and update `device` in `disko/mullvad-vm.nix`.
