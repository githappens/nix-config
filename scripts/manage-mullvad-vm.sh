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
#   ./scripts/manage-mullvad-vm.sh create              # create VM + boot ISO
#   ./scripts/manage-mullvad-vm.sh install <vm-ip>     # run nixos-anywhere after ISO is booted
#   ./scripts/manage-mullvad-vm.sh update [<vm-ip>]    # update flake, browser, and deploy

set -euo pipefail

VM_NAME="mullvad-vm"
RAM=2048
DISK=15000
CPUS=2
ISO="${NIXOS_ISO:-$HOME/ISOs/nixos-minimal-aarch64-linux.iso}"
FLAKE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BROWSER_PKG="$FLAKE_DIR/pkgs/mullvad-browser.nix"
VM_IP="${MULLVAD_VM_IP:-}"

create_vm() {
  echo "==> Creating Parallels VM: $VM_NAME"

  if prlctl list --all | grep -q "$VM_NAME"; then
    echo "VM '$VM_NAME' already exists. Delete it first or use a different name."
    exit 1
  fi

  prlctl create "$VM_NAME" -o linux --no-hdd
  prlctl set "$VM_NAME" --device-add hdd --size "$DISK"
  prlctl set "$VM_NAME" --device-set cdrom0 --image "$ISO" --connect
  prlctl set "$VM_NAME" --memsize "$RAM" --cpus "$CPUS"
  prlctl set "$VM_NAME" --device-set net0 --type shared
  prlctl set "$VM_NAME" --on-window-close shutdown

  # Share the flake repo into the VM (useful for future nixos-rebuild)
  prlctl set "$VM_NAME" --shf-host-add nix-config --path "$FLAKE_DIR" --mode rw

  echo ""
  echo "==> VM created. Next steps:"
  echo "  1. Start the VM:  prlctl start $VM_NAME"
  echo "  2. In the VM console, set a root password:"
  echo "       passwd"
  echo "  3. Find the VM IP:"
  echo "       ip addr show enp0s5"
  echo "  4. Run the install:"
  echo "       ./scripts/manage-mullvad-vm.sh install <vm-ip>"
}

install_nixos() {
  local vm_ip="${1:?Usage: $0 install <vm-ip>}"

  if [ ! -f "$FLAKE_DIR/secrets/mullvad-wg.conf" ]; then
    echo "ERROR: secrets/mullvad-wg.conf not found."
    echo "Copy secrets/mullvad-wg.conf.example and fill in your Mullvad config."
    exit 1
  fi

  # Prepare extra-files tree: deploy the WireGuard secret outside the Nix store.
  local extra_files
  extra_files="$(mktemp -d)"
  mkdir -p "$extra_files/etc/mullvad-wg"
  cp "$FLAKE_DIR/secrets/mullvad-wg.conf" "$extra_files/etc/mullvad-wg/wg0.conf"
  chmod 600 "$extra_files/etc/mullvad-wg/wg0.conf"

  echo "==> Installing NixOS on $VM_NAME via nixos-anywhere..."
  echo "    Target: root@$vm_ip"
  echo "    Flake:  $FLAKE_DIR#mullvad-vm"
  echo ""

  nix run github:nix-community/nixos-anywhere -- \
    --flake "$FLAKE_DIR#mullvad-vm" \
    --build-on-remote \
    --extra-files "$extra_files" \
    root@"$vm_ip"

  rm -rf "$extra_files"

  echo ""
  echo "==> Done. The VM will reboot into the installed system."
  echo "    Disconnect the ISO: prlctl set $VM_NAME --device-set cdrom0 --disconnect"
  echo "    Login: user / changeme"
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
    # Ask Parallels for the VM's IP
    ip=$(prlctl exec "$VM_NAME" ip -4 -o addr show enp0s5 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
  fi
  if [ -z "$ip" ]; then
    echo "ERROR: Could not determine VM IP. Pass it as an argument or set MULLVAD_VM_IP." >&2
    exit 1
  fi
  echo "$ip"
}

update_vm() {
  local vm_ip
  vm_ip=$(resolve_vm_ip "${1:-}")

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
  rsync -avz --exclude='.git' --exclude='secrets' "$FLAKE_DIR/" "user@${vm_ip}:/tmp/nix-config/"

  # Copy secrets separately (not via rsync to avoid leaking to logs)
  if [ -f "$FLAKE_DIR/secrets/mullvad-wg.conf" ]; then
    ssh "user@${vm_ip}" "mkdir -p /tmp/nix-config/secrets"
    scp -q "$FLAKE_DIR/secrets/mullvad-wg.conf" "user@${vm_ip}:/tmp/nix-config/secrets/"
  fi

  ssh "user@${vm_ip}" "sudo nixos-rebuild switch --flake /tmp/nix-config#mullvad-vm && sudo rm -rf /tmp/nix-config"

  echo ""
  echo "==> Update complete. Reboot the VM if needed: prlctl restart $VM_NAME"
}

case "${1:-create}" in
  create)  create_vm ;;
  install) install_nixos "${2:-}" ;;
  update)  update_vm "${2:-}" ;;
  *)
    echo "Usage: $0 [create|install <vm-ip>|update [<vm-ip>]]"
    exit 1
    ;;
esac
