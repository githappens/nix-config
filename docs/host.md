# Host Setup

Minimal nix-darwin config for the Apple Silicon Mac. Provides GPG agent with YubiKey SSH support for provisioning VMs. No dev tools — all development happens in the devbox VM.

## Prerequisites

- Apple Silicon Mac with macOS
- [Nix](https://install.determinate.systems/nix) (Determinate Systems installer)
- YubiKey with GPG keys (signing + authentication subkeys)
- [Parallels Desktop](https://www.parallels.com/) installed

## Step 1: Install Nix

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

Open a new terminal after installation.

## Step 2: Clone this repo

```bash
git clone <repo-url> ~/Developer/DevOps/nix-config
cd ~/Developer/DevOps/nix-config
```

## Step 3: Bootstrap nix-darwin

Insert your YubiKey, then run the bootstrap. First run installs nix-darwin itself — no prior installation needed:

```bash
sudo nix run nix-darwin -- switch --flake .#host
```

> **Note:** System activation requires root. If your account has admin privileges, `sudo` is enough. If you use a separate admin account, see [Split build/activate](#split-buildactivate-separate-admin-account) below.

This installs and configures:
- gnupg with YubiKey support (scdaemon)
- gpg-agent with SSH support and macOS pinentry
- zsh with GPG/SSH agent environment wiring

After this, `darwin-rebuild` is available for future updates:

```bash
sudo darwin-rebuild switch --flake .#host
```

## Step 4: Initialize YubiKey and extract SSH public key

Open a new shell (to pick up the gpg-agent env), then:

```bash
gpg --card-status && ssh-add -L > secrets/yubikey-ssh.pub
```

This creates the GPG key stubs from the YubiKey (no private key material on disk) and extracts the SSH public key for VM provisioning. Verify:

```bash
ssh-add -L
```

You should see your YubiKey's authentication key.

## What's next

The host is now ready to provision VMs:

- [Mullvad VM setup](mullvad-vm.md) — privacy browser kiosk
- [Devbox setup](devbox.md) — developer workstation

## Updating

```bash
sudo darwin-rebuild switch --flake .#host
```

If using a separate admin account, follow the [split build/activate](#split-buildactivate-separate-admin-account) flow instead.

## Split build/activate (separate admin account)

If your regular account can't `sudo` and you use a dedicated admin account, split the process: build as your regular user (who owns the repo), then activate as the admin.

### 1. Build (as your regular user)

From the repo directory (see Step 2):

```bash
nix build .#darwinConfigurations.host.system
```

This creates a `./result` symlink pointing to the built store path.

### 2. Activate (as admin user)

Switch to your admin account, then run from the same repo directory:

```bash
store_path=$(readlink result)
sudo nix-env -p /nix/var/nix/profiles/system --set "$store_path"
sudo "$store_path/activate"
```

The nix store is world-readable, so the admin user can access the built derivation without needing to read the git repo.

> **Note:** Both steps are needed — `nix-env --set` updates the system profile (enables `darwin-rebuild --rollback`), `activate` applies the configuration.

## What this config provides

- `gpg-agent` running as launchd service with SSH support
- `scdaemon` configured for YubiKey (ccid disabled)
- `SSH_AUTH_SOCK` pointing to gpg-agent socket (YubiKey serves SSH keys)
- macOS pinentry for GPG passphrase/PIN prompts
- Nothing else — the host stays minimal
