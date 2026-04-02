# Nix Config

Declarative configurations for a locked-down Apple Silicon Mac and its VMs.

## Architecture

```
Host (macOS, nix-darwin)
├── YubiKey GPG/SSH agent (provisions all VMs)
├── Parallels Desktop
│   ├── mullvad-vm (NixOS) — Mullvad Browser kiosk, WireGuard full tunnel
│   └── devbox (macOS Tahoe, nix-darwin) — developer workstation
└── ~/Work (shared folder, mounted in devbox)
```

All VMs are ephemeral — Parallels Rollback Mode reverts them to a clean snapshot on shutdown. Persistent state (project repos, tool configs) lives on the host's shared folder.

## Configurations

| Target | System | Flake output | Guide |
|--------|--------|-------------|-------|
| **host** | macOS (nix-darwin) | `darwinConfigurations.host` | [docs/host.md](docs/host.md) |
| **mullvad-vm** | NixOS (aarch64-linux) | `nixosConfigurations.mullvad-vm` | [docs/mullvad-vm.md](docs/mullvad-vm.md) |
| **devbox** | macOS Tahoe (nix-darwin) | `darwinConfigurations.devbox` | [docs/devbox.md](docs/devbox.md) |

## Getting started

Start with the [host setup guide](docs/host.md). It only requires:

1. [Nix](https://install.determinate.systems/nix) (Determinate Systems installer)
2. This repo
3. A YubiKey with GPG keys

From there, the host can provision any VM.
