# Devbox VM Dotfiles — Design Spec

## Overview

Add a `darwinConfigurations.devbox` flake output using nix-darwin + home-manager to declaratively manage the developer profile (GPG, SSH, git signing, zsh) for an ephemeral macOS Tahoe devbox VM. The existing mullvad-vm config is untouched.

## Architecture

```
New Mac (locked-down host, minimal — no dev profile)
├── nix-config repo cloned here
├── Mullvad VM (NixOS, existing)
├── Devbox VM (macOS Tahoe, nix-darwin + home-manager) ← this spec
│   ├── Ephemeral: resets to snapshot on shutdown
│   ├── Host-mapped drive: project repos + persistent tool state
│   └── Developer profile: GPG, SSH, git signing, zsh
└── Possibly other VMs
```

## Flake changes

Two new inputs:

```nix
nix-darwin.url = "github:LnL7/nix-darwin";
nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

home-manager.url = "github:nix-community/home-manager";
home-manager.inputs.nixpkgs.follows = "nixpkgs";
```

One new output (alongside existing `nixosConfigurations.mullvad-vm`):

```nix
darwinConfigurations.devbox = nix-darwin.lib.darwinSystem {
  system = "aarch64-darwin";
  modules = [
    home-manager.darwinModules.home-manager
    ./modules/devbox.nix
  ];
};
```

## File layout

```
modules/
├── mullvad-vm.nix          (existing, untouched)
├── hardware-parallels.nix  (existing, untouched)
└── devbox.nix              (new — nix-darwin system config, imports home-manager)

home/
├── gpg.nix                 (gpg-agent.conf, scdaemon.conf, YubiKey support)
├── ssh.nix                 (SSH client config, host entries — no private keys)
├── git.nix                 (signing key, user identity, gpgsign=true)
└── shell.nix               (zsh — GPG/SSH agent env vars, mapped drive paths)
```

`modules/devbox.nix` imports home-manager with the user profile:

```nix
home-manager.users."user" = { ... }: {
  imports = [
    ../home/gpg.nix
    ../home/ssh.nix
    ../home/git.nix
    ../home/shell.nix
  ];
};
```

## Module details

### home/gpg.nix

- `programs.gpg.enable = true`
- `services.gpg-agent`: enabled, SSH support on, macOS pinentry
- `scdaemon.conf` via `home.file` (YubiKey reader settings)

### home/ssh.nix

- `programs.ssh.enable = true`
- `matchBlocks` for: `github.com` (YubiKey), `github-secondary` (id_ed25519), `backrest` (id_backrest)
- No private keys — those are manually provisioned

### home/git.nix

Replaces `set-git-signing-config.sh` entirely:

- `userName = "Bence Kovacs"`
- `userEmail = "23636204+githappens@users.noreply.github.com"`
- `signing.key = "3BEF0F1F86B63AE0"`
- `signing.signByDefault = true`
- `extraConfig.gpg.program = "gpg"`

### home/shell.nix

- `programs.zsh.enable = true`
- `initExtra`: `GPG_TTY`, gpg-agent refresh, persistent tool state env vars (e.g., `CLAUDE_CONFIG_DIR` pointing to mapped drive)

## Secrets & provisioning

Same pattern as mullvad-vm:

1. Private SSH keys (`id_ed25519`, `id_backrest`) stored in `secrets/` (gitignored)
2. Manually copied into VM via scp before snapshotting
3. `id_yubikey.pub` regenerated at runtime from `ssh-add -L`

Management script (`scripts/manage-devbox-vm.sh` or extending existing):

1. Create Parallels macOS Tahoe VM with privacy hardening
2. Install nix + nix-darwin, deploy `darwin-rebuild switch --flake .#devbox`
3. Copy private keys into `~/.ssh/`, set permissions
4. Configure host drive mapping (Parallels shared folder)
5. Snapshot clean baseline, enable rollback mode

## Persistence model

| What | Where | Survives reset? |
|------|-------|-----------------|
| System/dotfile config | nix-darwin + home-manager (baked into snapshot) | Yes (in snapshot) |
| Private SSH keys | `~/.ssh/` (baked into snapshot) | Yes (in snapshot) |
| Project repos | Host-mapped drive | Yes |
| Claude Code config/memory | Host-mapped drive | Yes |
| GPG key stubs, trustdb | Regenerated at runtime (`--card-status`) | Rebuilt |
| `id_yubikey.pub` | Regenerated (`ssh-add -L`) | Rebuilt |
| `known_hosts` | Regenerated on first connect | Rebuilt |
| Browser state, tmp, etc. | VM local disk | No (ephemeral) |

## Out of scope

- Host nix-darwin config (host stays minimal, no dev profile)
- Claude Code config contents (lives on mapped drive, not in this repo)
- Actual project repos
- VM creation automation (separate task, builds on mullvad-vm patterns)
