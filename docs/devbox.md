# Devbox Setup

macOS Tahoe VM with nix-darwin + home-manager for a full developer workstation. Ephemeral — reverts to clean snapshot on shutdown. Project repos and tool configs persist via host-mapped shared folder.

## Architecture

```
devbox (macOS Tahoe, nix-darwin + home-manager)
├── GPG agent with YubiKey SSH support
├── Git with GPG commit signing
├── SSH config (GitHub, infrastructure hosts)
├── Zsh with aliases and utilities
└── ~/Work → host ~/Work (Parallels shared folder, persistent)
```

## Prerequisites

- [Host setup](host.md) completed (Nix, nix-darwin, YubiKey SSH working)
- A macOS template VM in Parallels (see below)

## One-time: Create the macOS template VM

This is done once by hand. The template is then cloned for each new VM.

### 1. Get a macOS Tahoe IPSW

Download or source a macOS Tahoe IPSW (or create a VM from Parallels' built-in installer).

### 2. Create the VM in Parallels

Create a new macOS VM from the IPSW. Go through the macOS setup assistant:
- Create a user account named `user`
- Skip Apple ID sign-in
- Set a password (you'll use SSH keys going forward)

Install Parallels Tools when prompted (or via Devices > Install Parallels Tools).

### 3. macOS settings (in the VM GUI)

These can't be managed by nix-darwin — do them once in the template.

**Security / access:**
- System Settings > Users & Groups > Automatic Login > select `user`
- Passwordless sudo (in Terminal):
  ```bash
  sudo visudo -f /etc/sudoers.d/nopasswd
  # Add: user ALL=(ALL) NOPASSWD: ALL
  ```

**Privacy / noise reduction:**
- System Settings > Siri & Spotlight > disable Siri
- System Settings > Siri & Spotlight > Spotlight > disable web/Siri suggestions
- System Settings > Privacy & Security > Analytics & Improvements > disable all
- System Settings > Privacy & Security > Apple Advertising > disable Personalized Ads
- System Settings > General > Software Update > Automatic Updates > disable all

**Power / display:**
- System Settings > Lock Screen > set all timers to Never
- System Settings > Displays > disable True Tone (if available)

**Liquid Glass (macOS 26.0.x only):**
```bash
defaults write -g com.apple.SwiftUI.DisableSolarium -bool YES
```
> This flag was removed in macOS 26.1+. On newer versions, use System Settings > Accessibility > Display > Reduce Transparency and System Settings > Appearance > Liquid Glass > Tinted.

**Remove bloatware** (frees ~5GB):
```bash
sudo rm -rf /Applications/GarageBand.app
sudo rm -rf /Applications/iMovie.app
sudo rm -rf /Applications/Keynote.app
sudo rm -rf /Applications/Pages.app
sudo rm -rf /Applications/Numbers.app
```

### 4. Enable Remote Login (SSH)

System Settings > General > Sharing > Remote Login > enable for `user`

### 5. Add YubiKey SSH public key

From the host:

```bash
ssh-copy-id -f -i secrets/yubikey-ssh.pub user@<template-vm-ip>
```

Verify you can SSH in without a password:

```bash
ssh user@<template-vm-ip>
```

### 6. Install Nix in the template

SSH into the template VM and install Nix:

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

### 7. Snapshot and shut down

```bash
prlctl stop <template-vm-name>
prlctl snapshot <template-vm-name> --name "base" --description "Clean macOS Tahoe with Nix, SSH, auto-login configured."
```

Do not enable rollback mode on the template — it's a base image, not a running VM.

## Provisioning a devbox from the template

The provisioning script automates: clone, privacy hardening, shared folder, nix-darwin deploy, SSH key copy, snapshot with rollback.

```bash
./scripts/provision-devbox.sh [<template-name>] [<vm-name>] [<vm-ip>]
```

Defaults: `macOS-Tahoe-template` and `dev-env`. The script is idempotent — if the VM already exists it skips clone/hardening and re-deploys config.

Examples:

```bash
./scripts/provision-devbox.sh                                          # defaults
./scripts/provision-devbox.sh macOS-Tahoe-template staging             # custom name
./scripts/provision-devbox.sh macOS-Tahoe-template dev-env 10.211.55.5 # manual IP
```

## Persistence model

| What | Where | Survives reset? |
|------|-------|-----------------|
| System/dotfile config | nix-darwin + home-manager (in snapshot) | Yes |
| Private SSH keys | `~/.ssh/` (in snapshot) | Yes |
| Project repos | `~/Work` (host shared folder) | Yes |
| Tool configs (Claude Code, etc.) | `~/Work` (host shared folder) | Yes |
| GPG key stubs, trustdb | Regenerated (`gpg --card-status`) | Rebuilt |
| `known_hosts` | Regenerated on first connect | Rebuilt |
| Everything else | VM local disk | No (ephemeral) |

## Updating

After changing the nix-config:

```bash
rsync -avz --exclude='.git' --exclude='secrets' \
  . user@<devbox-ip>:/tmp/nix-config/

ssh user@<devbox-ip> \
  "sudo darwin-rebuild switch --flake /tmp/nix-config#devbox && rm -rf /tmp/nix-config"
```

Then re-snapshot if you want the update to persist across rollbacks:

```bash
prlctl stop devbox
# delete old snapshot, create new one, re-enable rollback
prlctl snapshot devbox --name "clean" --description "Post-update baseline."
prlctl set devbox --undo-disks discard
prlctl start devbox
```

## Day-to-day usage

```bash
prlctl start devbox             # Start the VM
prlctl stop devbox              # Stop (reverts to snapshot)
ssh user@<devbox-ip>            # SSH in (uses YubiKey via gpg-agent)
```

## What this config provides

- GPG agent with YubiKey SSH support and macOS pinentry
- SSH config for GitHub (primary + secondary), infrastructure hosts
- Git with GPG commit signing (`3BEF0F1F86B63AE0`)
- Zsh with git aliases, `gum`-based directory navigation (`cds`/`cdr`), script templating
- `neovim`, `gum`, `gnupg` installed
- Bash script template at `~/scripts/.scripttemplate`
