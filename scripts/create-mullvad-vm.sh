#!/usr/bin/env bash
# Create and provision the Mullvad Browser kiosk VM in Parallels.
#
# Prerequisites:
#   - Nix installed on the host (determinate.systems installer)
#   - NixOS minimal ISO downloaded (aarch64) to ~/ISOs/
#   - secrets/mullvad-wg.conf populated with your Mullvad WireGuard config
#   - Parallels Desktop installed
#
# Usage:
#   ./scripts/create-mullvad-vm.sh           # create + boot ISO
#   ./scripts/create-mullvad-vm.sh install   # run nixos-anywhere after ISO is booted

set -euo pipefail

VM_NAME="mullvad-vm"
RAM=2048
DISK=15000
CPUS=2
ISO="${NIXOS_ISO:-$HOME/ISOs/nixos-minimal-aarch64-linux.iso}"
FLAKE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

create_vm() {
  echo "==> Creating Parallels VM: $VM_NAME"

  if prlctl list --all | grep -q "$VM_NAME"; then
    echo "VM '$VM_NAME' already exists. Delete it first or use a different name."
    exit 1
  fi

  prlctl create "$VM_NAME" -o linux-2.6 --no-hdd
  prlctl set "$VM_NAME" --device-add hdd --type expanding --size "$DISK"
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
  echo "       ./scripts/create-mullvad-vm.sh install <vm-ip>"
}

install_nixos() {
  local vm_ip="${1:?Usage: $0 install <vm-ip>}"

  if [ ! -f "$FLAKE_DIR/secrets/mullvad-wg.conf" ]; then
    echo "ERROR: secrets/mullvad-wg.conf not found."
    echo "Copy secrets/mullvad-wg.conf.example and fill in your Mullvad config."
    exit 1
  fi

  echo "==> Installing NixOS on $VM_NAME via nixos-anywhere..."
  echo "    Target: root@$vm_ip"
  echo "    Flake:  $FLAKE_DIR#mullvad-vm"
  echo ""

  nix run github:nix-community/nixos-anywhere -- \
    --flake "$FLAKE_DIR#mullvad-vm" \
    --build-on-remote \
    root@"$vm_ip"

  echo ""
  echo "==> Done. The VM will reboot into the installed system."
  echo "    Disconnect the ISO: prlctl set $VM_NAME --device-set cdrom0 --disconnect"
  echo "    Login: user / changeme"
}

case "${1:-create}" in
  create)  create_vm ;;
  install) install_nixos "${2:-}" ;;
  *)
    echo "Usage: $0 [create|install <vm-ip>]"
    exit 1
    ;;
esac
