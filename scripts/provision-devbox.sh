#!/usr/bin/env bash
# Provision a macOS devbox VM from a Parallels template.
#
# Clones a macOS template, applies privacy hardening, shared folders,
# deploys nix-darwin + home-manager config, copies SSH keys, and snapshots.
#
# Prerequisites:
#   - Template VM with macOS, Nix (Determinate), SSH enabled, auto-login
#   - YubiKey SSH public key at secrets/yubikey-ssh.pub
#   - Private SSH keys at ~/.ssh/id_ed25519 and ~/.ssh/id_rsa_BD
#
# Usage:
#   ./scripts/provision-devbox.sh [<template-name>] [<vm-name>]
#
#   Defaults: template = macOS-Tahoe-template, vm = dev-env

set -euo pipefail

TEMPLATE="${1:-macOS-Tahoe-template}"
VM_NAME="${2:-dev-env}"
VM_USER="user"
FLAKE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SSH_PUBKEY="$FLAKE_DIR/secrets/yubikey-ssh.pub"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5"

ensure_ssh_pubkey() {
  if [ ! -f "$SSH_PUBKEY" ]; then
    echo "==> Extracting YubiKey SSH public key..."
    if ! ssh-add -L > "$SSH_PUBKEY" 2>/dev/null || [ ! -s "$SSH_PUBKEY" ]; then
      rm -f "$SSH_PUBKEY"
      echo "ERROR: No SSH keys found in agent. Is your YubiKey inserted and gpg-agent running?"
      echo "Try: gpg --card-status && ssh-add -L"
      exit 1
    fi
    echo "    Saved to $SSH_PUBKEY"
  fi
}

get_vm_ip() {
  local max_attempts=40
  local attempt=0
  local ip=""

  echo "==> Waiting for VM to get an IP address..." >&2
  while [ $attempt -lt $max_attempts ]; do
    ip=$(prlctl list "$VM_NAME" --full --json 2>/dev/null \
      | grep -o '"ip_configured":[ ]*"[^"]*"' \
      | head -1 \
      | sed 's/.*"ip_configured":[ ]*"\([^"]*\)".*/\1/') || true
    if [ -n "$ip" ] && [ "$ip" != "-" ]; then
      echo "    VM IP: $ip" >&2
      echo "$ip"
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 3
  done

  echo "ERROR: Could not determine VM IP after $((max_attempts * 3))s." >&2
  exit 1
}

wait_for_ssh() {
  local ip="$1"
  local max_attempts=40
  local attempt=0

  echo "==> Waiting for SSH at $ip..."
  while [ $attempt -lt $max_attempts ]; do
    if ssh $SSH_OPTS -o BatchMode=yes "$VM_USER@$ip" true 2>/dev/null; then
      echo "    SSH is up."
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 3
  done

  echo "ERROR: SSH not reachable at $ip after $((max_attempts * 3))s"
  exit 1
}

get_snapshot_id() {
  prlctl snapshot-list "$VM_NAME" --json 2>/dev/null \
    | grep -o '"{[^"]*}"' \
    | head -1 \
    | tr -d '"' || true
}

# ── Preflight checks ─────────────────────────────────────────────

if ! prlctl list --all | grep -q "$TEMPLATE"; then
  echo "ERROR: Template '$TEMPLATE' not found in Parallels."
  echo "Available VMs:"
  prlctl list --all
  exit 1
fi

if prlctl list --all | grep -q "$VM_NAME"; then
  echo "ERROR: VM '$VM_NAME' already exists. Delete it first or choose a different name."
  exit 1
fi

ensure_ssh_pubkey

# ── Step 1: Clone template ───────────────────────────────────────

echo "==> Cloning '$TEMPLATE' → '$VM_NAME'"
prlctl clone "$TEMPLATE" --name "$VM_NAME"

# ── Step 2: Privacy hardening ────────────────────────────────────

echo "==> Applying privacy hardening..."
prlctl set "$VM_NAME" --isolate-vm on
prlctl set "$VM_NAME" --auto-share-camera off
prlctl set "$VM_NAME" --auto-share-bluetooth off 2>/dev/null || true
prlctl set "$VM_NAME" --auto-share-smart-card off 2>/dev/null || true
prlctl set "$VM_NAME" --shared-clipboard off
prlctl set "$VM_NAME" --shared-cloud off
prlctl set "$VM_NAME" --sh-app-host-to-guest off
prlctl set "$VM_NAME" --sh-app-guest-to-host off
prlctl set "$VM_NAME" --shared-profile off
prlctl set "$VM_NAME" --sync-host-printers off

# ── Step 3: Shared folder ────────────────────────────────────────

echo "==> Adding shared folder: ~/Work → /Volumes/Work"
prlctl set "$VM_NAME" --shf-host-add Work --path "$HOME/Work" --enable

# ── Step 4: Start and wait for SSH ───────────────────────────────

echo "==> Starting VM..."
prlctl start "$VM_NAME"

vm_ip=$(get_vm_ip)
wait_for_ssh "$vm_ip"

# Symlink shared folder
ssh $SSH_OPTS "$VM_USER@$vm_ip" "ln -sf /Volumes/Work ~/Work"

# ── Step 5: Deploy nix-darwin config ─────────────────────────────

echo "==> Deploying nix-darwin config..."
rsync -avz -e "ssh $SSH_OPTS" --exclude='.git' --exclude='secrets' \
  "$FLAKE_DIR/" "$VM_USER@${vm_ip}:/tmp/nix-config/"

ssh $SSH_OPTS "$VM_USER@$vm_ip" \
  "nix run nix-darwin -- switch --flake /tmp/nix-config#devbox && rm -rf /tmp/nix-config"

# ── Step 6: Copy private SSH keys ────────────────────────────────

echo "==> Copying SSH keys..."
for key in id_ed25519 id_rsa_BD; do
  if [ -f "$HOME/.ssh/$key" ]; then
    scp $SSH_OPTS "$HOME/.ssh/$key" "$VM_USER@${vm_ip}:~/.ssh/$key"
    ssh $SSH_OPTS "$VM_USER@$vm_ip" "chmod 600 ~/.ssh/$key"
    echo "    Copied $key"
  else
    echo "    Skipping $key (not found at ~/.ssh/$key)"
  fi
done

# ── Step 7: Snapshot and enable rollback ─────────────────────────

echo "==> Creating clean snapshot and enabling rollback..."
prlctl stop "$VM_NAME" --kill 2>/dev/null || true
sleep 5
prlctl snapshot "$VM_NAME" --name "clean" --description "Post-provision baseline."
prlctl set "$VM_NAME" --undo-disks discard
prlctl start "$VM_NAME"

echo ""
echo "==> Done! VM '$VM_NAME' is running."
echo "    ssh $VM_USER@$vm_ip"
echo ""
echo "    Updates: rsync config + darwin-rebuild switch"
echo "    See docs/devbox.md for the update workflow."
