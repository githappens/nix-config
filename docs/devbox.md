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

### 3. Enable Remote Login (SSH)

System Settings > General > Sharing > Remote Login > enable for `user`

### 4. Add YubiKey SSH public key

From the host:

```bash
ssh-copy-id -f -i secrets/yubikey-ssh.pub user@<template-vm-ip>
```

Verify you can SSH in without a password:

```bash
ssh user@<template-vm-ip>
```

### 5. Install Nix in the template

SSH into the template VM and install Nix:

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

### 6. Shut down and keep as template

```bash
prlctl stop <template-vm-name>
```

Do not enable rollback mode on the template — it's a base image, not a running VM.

## Provisioning a devbox from the template

### Step 1: Clone the template

```bash
prlctl clone <template-vm-name> --name devbox
```

### Step 2: Privacy hardening

```bash
prlctl set devbox --isolate-vm on
prlctl set devbox --auto-share-camera off
prlctl set devbox --shared-clipboard off
prlctl set devbox --shared-cloud off
prlctl set devbox --sh-app-host-to-guest off
prlctl set devbox --sh-app-guest-to-host off
prlctl set devbox --shared-profile off
prlctl set devbox --sync-host-printers off
```

### Step 3: Add shared folder

```bash
prlctl set devbox --shf-host-add Work --path "$HOME/Work" --enable
```

In the VM, this mounts at `/Volumes/Work` (or configure Parallels to mount elsewhere). Symlink it:

```bash
ssh user@<devbox-ip> "ln -sf /Volumes/Work ~/Work"
```

### Step 4: Start and deploy config

```bash
prlctl start devbox
```

Wait for SSH, then deploy:

```bash
# Copy the repo into the VM
rsync -avz --exclude='.git' --exclude='secrets' \
  . user@<devbox-ip>:/tmp/nix-config/

# Bootstrap nix-darwin with the devbox config
ssh user@<devbox-ip> \
  "nix run nix-darwin -- switch --flake /tmp/nix-config#devbox && rm -rf /tmp/nix-config"
```

### Step 5: Copy private SSH keys

```bash
scp ~/.ssh/id_ed25519 user@<devbox-ip>:~/.ssh/id_ed25519
scp ~/.ssh/id_rsa_BD user@<devbox-ip>:~/.ssh/id_rsa_BD
ssh user@<devbox-ip> "chmod 600 ~/.ssh/id_ed25519 ~/.ssh/id_rsa_BD"
```

### Step 6: Snapshot and enable rollback

```bash
prlctl stop devbox
prlctl snapshot devbox --name "clean" --description "Post-provision baseline."
prlctl set devbox --undo-disks discard
prlctl start devbox
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
  "darwin-rebuild switch --flake /tmp/nix-config#devbox && rm -rf /tmp/nix-config"
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
