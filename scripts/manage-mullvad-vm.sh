#!/usr/bin/env bash
# Manage the Mullvad Browser kiosk VM in Parallels.
#
# Prerequisites:
#   - Nix installed on the host (determinate.systems installer)
#   - NixOS minimal ISO downloaded (aarch64) to ~/ISOs/
#   - secrets/mullvad-wg.conf populated with your Mullvad WireGuard config
#   - Parallels Desktop installed
#
# Usage:
#   ./scripts/manage-mullvad-vm.sh create              # create VM, boot ISO, install NixOS
#   ./scripts/manage-mullvad-vm.sh update [<vm-ip>]    # update flake, browser, and deploy

set -euo pipefail

# Re-launch inside nix develop if git or ssh aren't available
if ! command -v git &>/dev/null || ! command -v ssh &>/dev/null; then
  exec nix develop "$(cd "$(dirname "$0")/.." && pwd)" --command "$0" "$@"
fi


VM_NAME="mullvad-vm"
RAM=8192
DISK=15000
CPUS=4
ISO="${NIXOS_ISO:-$HOME/ISOs/nixos-minimal-aarch64-linux.iso}"
FLAKE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BROWSER_PKG="$FLAKE_DIR/pkgs/mullvad-browser.nix"
SSH_KEY="$FLAKE_DIR/secrets/vm-ssh-key"
VM_IP="${MULLVAD_VM_IP:-}"

ensure_ssh_key() {
  if [ ! -f "$SSH_KEY" ]; then
    echo "==> Generating SSH key for VM access..."
    ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "mullvad-vm-deploy"
    echo "    Created $SSH_KEY"
  fi
}

wait_for_ssh() {
  local ip="$1"
  local max_attempts=60
  local attempt=0

  echo "==> Waiting for SSH at $ip..."
  while [ $attempt -lt $max_attempts ]; do
    if ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o BatchMode=yes root@"$ip" true 2>/dev/null; then
      echo "    SSH is up."
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 3
  done

  echo "ERROR: SSH not reachable at $ip after $((max_attempts * 3))s"
  exit 1
}

get_vm_ip() {
  # Get the VM's IP from Parallels (works even without guest tools)
  local max_attempts=30
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

  echo "ERROR: Could not determine VM IP. Check the VM console for the IP and pass it manually." >&2
  exit 1
}

create_vm() {
  local vm_ip="${1:-}"

  echo "==> Creating Parallels VM: $VM_NAME"

  if prlctl list --all | grep -q "$VM_NAME"; then
    echo "VM '$VM_NAME' already exists. Delete it first or use a different name."
    exit 1
  fi

  ensure_ssh_key

  prlctl create "$VM_NAME" -o linux --no-hdd
  prlctl set "$VM_NAME" --device-add hdd --size "$DISK"
  prlctl set "$VM_NAME" --device-set cdrom0 --image "$ISO" --connect
  prlctl set "$VM_NAME" --memsize "$RAM" --cpus "$CPUS"
  prlctl set "$VM_NAME" --device-set net0 --type shared
  prlctl set "$VM_NAME" --on-window-close shutdown
  prlctl set "$VM_NAME" --camera-sharing off 2>/dev/null || true
  prlctl set "$VM_NAME" --microphone-sharing off 2>/dev/null || true

  echo ""
  echo "==> Starting VM with NixOS installer ISO..."
  prlctl start "$VM_NAME"

  echo ""
  echo "==> Waiting for installer to boot..."
  echo "    In the VM console, run:  sudo passwd"
  echo "    Then press Enter here to continue."
  read -r

  if [ -z "$vm_ip" ]; then
    vm_ip=$(resolve_vm_ip "")
  fi

  install_nixos "$vm_ip"
}

install_nixos() {
  local vm_ip="$1"

  if [ ! -f "$FLAKE_DIR/secrets/mullvad-wg.conf" ]; then
    echo "ERROR: secrets/mullvad-wg.conf not found."
    echo "Copy secrets/mullvad-wg.conf.example and fill in your Mullvad config."
    exit 1
  fi

  ensure_ssh_key

  # Prepare extra-files tree
  local extra_files
  extra_files="$(mktemp -d)"

  mkdir -p "$extra_files/etc/mullvad-wg"
  cp "$FLAKE_DIR/secrets/mullvad-wg.conf" "$extra_files/etc/mullvad-wg/wg0.conf"
  chmod 600 "$extra_files/etc/mullvad-wg/wg0.conf"

  mkdir -p "$extra_files/home/user/.ssh"
  cp "${SSH_KEY}.pub" "$extra_files/home/user/.ssh/authorized_keys"
  chmod 700 "$extra_files/home/user/.ssh"
  chmod 600 "$extra_files/home/user/.ssh/authorized_keys"

  echo "==> Installing NixOS on $VM_NAME via nixos-anywhere..."
  echo "    Target: root@$vm_ip"
  echo "    Flake:  $FLAKE_DIR#mullvad-vm"
  echo ""

  nix run github:nix-community/nixos-anywhere -- \
    --flake "$FLAKE_DIR#mullvad-vm" \
    --build-on remote \
    --extra-files "$extra_files" \
    root@"$vm_ip"

  rm -rf "$extra_files"

  echo ""
  echo "==> Install complete. Disconnecting ISO and restarting VM..."
  prlctl stop "$VM_NAME" --kill 2>/dev/null || true
  prlctl set "$VM_NAME" --device-set cdrom0 --disconnect
  prlctl start "$VM_NAME"

  echo "==> VM is booting from disk."
  echo "    Login: user / changeme"
  echo "    Updates: ./scripts/manage-mullvad-vm.sh update"
}

update_browser() {
  echo "==> Checking for Mullvad Browser updates..."

  local current_version
  current_version=$(grep 'version = ' "$BROWSER_PKG" | head -1 | sed 's/.*"\(.*\)".*/\1/')
  echo "    Current version: $current_version"

  # Fetch the latest alpha version from the CDN
  local latest_version
  latest_version=$(curl -sL "https://cdn.mullvad.net/browser/" \
    | grep -oE '[0-9]+\.[0-9]+a[0-9]+' \
    | sort -V \
    | tail -1)

  if [ -z "$latest_version" ]; then
    echo "    Could not determine latest version. Skipping browser update."
    return 1
  fi

  echo "    Latest alpha version: $latest_version"

  if [ "$current_version" = "$latest_version" ]; then
    echo "    Already up to date."
    return 0
  fi

  echo "    Updating $current_version -> $latest_version"

  # Prefetch the new tarball and get the SRI hash
  local url="https://cdn.mullvad.net/browser/${latest_version}/mullvad-browser-linux-aarch64-${latest_version}.tar.xz"
  echo "    Fetching hash for $url ..."
  local new_hash
  new_hash=$(nix-prefetch-url --type sha256 --unpack "$url" 2>/dev/null | xargs nix hash convert --hash-algo sha256 --to sri)

  if [ -z "$new_hash" ]; then
    echo "    ERROR: Failed to prefetch new version. Is there an aarch64 build?"
    return 1
  fi

  echo "    New hash: $new_hash"

  # Update the package file
  sed -i '' "s/version = \"${current_version}\"/version = \"${latest_version}\"/" "$BROWSER_PKG"
  sed -i '' "s|hash = \".*\"|hash = \"${new_hash}\"|" "$BROWSER_PKG"

  echo "    Updated pkgs/mullvad-browser.nix"
}

resolve_vm_ip() {
  local ip="${1:-$VM_IP}"
  if [ -z "$ip" ]; then
    ip=$(prlctl list "$VM_NAME" --full --json 2>/dev/null \
      | grep -o '"ip_configured":[ ]*"[^"]*"' \
      | head -1 \
      | sed 's/.*"ip_configured":[ ]*"\([^"]*\)".*/\1/') || true
  fi
  if [ -z "$ip" ] || [ "$ip" = "-" ]; then
    echo "ERROR: Could not determine VM IP. Pass it as an argument or set MULLVAD_VM_IP." >&2
    exit 1
  fi
  echo "$ip"
}

update_vm() {
  local vm_ip
  vm_ip=$(resolve_vm_ip "${1:-}")

  ensure_ssh_key

  echo "==> Updating Mullvad VM at $vm_ip"
  echo ""

  # Step 1: Update flake inputs
  echo "==> Updating flake inputs..."
  cd "$FLAKE_DIR"
  nix flake update

  # Step 2: Check for browser updates
  echo ""
  update_browser || true

  # Step 3: Deploy to VM
  echo ""
  echo "==> Deploying to VM..."
  local ssh_opts="-i $SSH_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

  rsync -avz -e "ssh $ssh_opts" --exclude='.git' --exclude='secrets' \
    "$FLAKE_DIR/" "user@${vm_ip}:/tmp/nix-config/"

  # Copy secrets separately
  if [ -f "$FLAKE_DIR/secrets/mullvad-wg.conf" ]; then
    ssh $ssh_opts "user@${vm_ip}" "mkdir -p /tmp/nix-config/secrets"
    scp -q $ssh_opts "$FLAKE_DIR/secrets/mullvad-wg.conf" "user@${vm_ip}:/tmp/nix-config/secrets/"
  fi

  ssh $ssh_opts "user@${vm_ip}" \
    "sudo nixos-rebuild switch --flake /tmp/nix-config#mullvad-vm && sudo rm -rf /tmp/nix-config"

  echo ""
  echo "==> Update complete. Restarting VM..."
  prlctl stop "$VM_NAME" --kill 2>/dev/null || true
  prlctl start "$VM_NAME"
}

case "${1:-create}" in
  create)  create_vm "${2:-}" ;;
  install) install_nixos "${2:?Usage: $0 install <vm-ip>}" ;;
  update)  update_vm "${2:-}" ;;
  *)
    echo "Usage: $0 [create|install <vm-ip>|update [<vm-ip>]]"
    exit 1
    ;;
esac
