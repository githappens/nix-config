# Nix Config

NixOS VM and host configurations.

## Current targets

- **mullvad-vm** — Mullvad Browser kiosk over WireGuard full tunnel VPN (Mullvad Browser 16.0a4 alpha, aarch64)

## Architecture

The mullvad-vm is a minimal NixOS VM running inside Parallels on Apple Silicon. It has no desktop environment — just cage (a Wayland kiosk compositor) launching Mullvad Browser fullscreen. All traffic goes through a WireGuard full tunnel to Mullvad VPN. DNS resolves through Mullvad's DNS server (`10.64.0.1`) inside the tunnel.

```
Host (macOS)
└── Parallels (shared/NAT networking)
    └── mullvad-vm (NixOS, aarch64-linux)
        ├── WireGuard full tunnel → Mullvad VPN
        ├── cage (Wayland kiosk)
        └── Mullvad Browser (fullscreen)
```

## Setup guide

### Step 1: Install Nix on the host

If you don't have Nix yet, install it with the Determinate Systems installer:

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh
```

Close and reopen your terminal, then verify:

```bash
nix --version
```

### Step 2: Clone this repo

```bash
git clone <your-remote> <local-path>
cd <local-path>
```

### Step 3: Download the NixOS minimal ISO

Download the **NixOS minimal ISO for aarch64-linux** from https://nixos.org/download/#nixos-iso and save it to `~/ISOs/`:

```bash
mkdir -p ~/ISOs
# Download the aarch64 minimal ISO — check the NixOS site for the current URL
curl -L -o ~/ISOs/nixos-minimal-aarch64-linux.iso \
  https://channels.nixos.org/nixos-25.05/latest-nixos-minimal-aarch64-linux.iso
```

### Step 4: Set up your Mullvad WireGuard config

Get a WireGuard config from https://mullvad.net/en/account/wireguard-config (pick a server, generate a key). Then:

```bash
cp secrets/mullvad-wg.conf.example secrets/mullvad-wg.conf
```

Paste your Mullvad config into `secrets/mullvad-wg.conf`. It should look like:

```ini
[Interface]
PrivateKey = your-actual-private-key
Address = 10.x.x.x/32, fc00:bbbb:bbbb:bb01::x:xxxx/128
DNS = 10.64.0.1

[Peer]
PublicKey = mullvad-server-pubkey
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = server-ip:51820
```

This file is gitignored and never leaves your machine.

### Step 5: Create the Parallels VM

```bash
./scripts/create-mullvad-vm.sh
```

This creates a Parallels VM (2 CPU, 2GB RAM, 15GB disk), attaches the NixOS ISO, and shares this repo into the VM.

### Step 6: Boot the ISO and prepare for install

Start the VM:

```bash
prlctl start mullvad-vm
```

A Parallels window will open with the NixOS installer. Once it boots to a shell:

```bash
# Set a root password (needed for SSH from the host)
passwd

# Find the VM's IP address
ip addr show enp0s5
```

Note the IP (usually something like `10.211.55.x`).

### Step 7: Verify the disk device name

Still inside the VM console:

```bash
lsblk
```

You should see the 15GB disk. If it's `/dev/sda`, you're good (that's what the disko config expects). If it's something else (e.g., `/dev/vda`), edit `disko/mullvad-vm.nix` on the host and update the `device` field before proceeding.

### Step 8: Install NixOS via nixos-anywhere

From the host terminal (not the VM console):

```bash
./scripts/create-mullvad-vm.sh install <vm-ip>
```

This runs `nixos-anywhere` which will:
1. SSH into the booted ISO
2. Partition and format the disk (via disko)
3. Install NixOS with the mullvad-vm configuration
4. Reboot the VM

The first build takes ~5-10 minutes since it downloads and builds everything inside the VM.

### Step 9: Post-install cleanup

After the VM reboots:

```bash
# Disconnect the ISO so it boots from disk
prlctl set mullvad-vm --device-set cdrom0 --disconnect

# Restart to boot cleanly from disk
prlctl restart mullvad-vm
```

### Step 10: Verify

The VM should boot into cage with Mullvad Browser fullscreen. To verify the VPN is working, navigate to https://mullvad.net/en/check inside the browser — it should show your Mullvad exit IP, not your real IP.

Login credentials: `user` / `changeme`

## Day-to-day usage

```bash
# Start the VM
prlctl start mullvad-vm

# Stop the VM (always shut down cleanly)
prlctl stop mullvad-vm

# SSH in for troubleshooting
ssh user@<vm-ip>
```

## Making config changes

After editing any `.nix` files, apply changes by SSH-ing into the VM:

```bash
ssh user@<vm-ip>
sudo nixos-rebuild switch --flake /mnt/psf/nix-config#mullvad-vm
```

Or from the VM console directly (the repo is shared at `/mnt/psf/nix-config`).

## Updating the Mullvad Browser alpha

When a new alpha is released at https://github.com/mullvad/mullvad-browser/releases:

1. Update `version` and `sha256` in `pkgs/mullvad-browser.nix`
2. Get the new hash:
   ```bash
   nix-prefetch-url https://github.com/mullvad/mullvad-browser/releases/download/<new-version>/mullvad-browser-linux-aarch64-<new-version>.tar.xz
   ```
3. Rebuild inside the VM: `sudo nixos-rebuild switch --flake /mnt/psf/nix-config#mullvad-vm`

Once the stable channel ships aarch64-linux builds, the `overlays/` and `pkgs/` directories can be removed and the flake simplified to use the upstream nixpkgs package.

## Troubleshooting

**Parallels Tools fail to build:** The kernel module can lag behind new kernels. Uncomment the `boot.kernelPackages` pin in `modules/hardware-parallels.nix`.

**WireGuard tunnel not coming up:** SSH in, check `sudo systemctl status wg-quick-wg0`. Verify `secrets/mullvad-wg.conf` is correct.

**Cage doesn't start / black screen:** SSH in, check `journalctl -u cage-tty1`. May need to verify Parallels GPU acceleration is working.

**Wrong disk device:** If `nixos-anywhere` fails during partitioning, boot the ISO again, run `lsblk`, and update the `device` in `disko/mullvad-vm.nix`.

## File structure

```
.
├── flake.nix                          # Flake: mullvad-vm target + disko input
├── modules/
│   ├── hardware-parallels.nix         # Parallels Tools, EFI boot, shared folders
│   └── mullvad-vm.nix                 # WireGuard tunnel, cage kiosk, firewall, user
├── disko/
│   └── mullvad-vm.nix                 # Declarative disk layout (GPT: EFI + ext4)
├── overlays/
│   └── mullvad-browser-aarch64.nix    # Overlay routing to custom aarch64 package
├── pkgs/
│   └── mullvad-browser.nix            # Mullvad Browser 16.0a4 alpha binary package
├── scripts/
│   └── create-mullvad-vm.sh           # VM creation + nixos-anywhere install helper
├── secrets/
│   ├── .gitkeep
│   └── mullvad-wg.conf.example        # WireGuard config template (fill in your own)
├── .gitignore
└── README.md
```
