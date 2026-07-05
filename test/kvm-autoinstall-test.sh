#!/usr/bin/env bash
# Reflash dress rehearsal: boot the real Ubuntu Server ISO with our rendered
# autoinstall seed inside a KVM VM *on the ThinkCentre itself* (true x86_64).
#
# Prereqs on the box (one-time):
#   sudo apt install -y qemu-system-x86 qemu-utils cloud-image-utils ovmf
# Plus a rendered seed: run autoinstall/make-usb.sh on the Mac and scp
# autoinstall/rendered/{user-data,meta-data} to the box next to this script,
# and download the ISO:
#   curl -LO https://releases.ubuntu.com/24.04/ubuntu-24.04.4-live-server-amd64.iso
#
# Then:  ./kvm-autoinstall-test.sh ubuntu-24.04.4-live-server-amd64.iso
#
# The VM installs unattended (~15 min), reboots, runs the first-boot
# convergence, and exposes SSH on localhost:2222:
#   ssh -p 2222 claudius@localhost   # then run test/verify.sh in the VM
set -euo pipefail

ISO="${1:?usage: $0 <ubuntu-live-server.iso>}"
DISK="claudius-test.qcow2"
SEED="seed.iso"

if [ ! -f user-data ] || [ ! -f meta-data ]; then
  echo "user-data/meta-data missing (render with make-usb.sh)"; exit 1
fi

cloud-localds "$SEED" user-data meta-data
qemu-img create -f qcow2 "$DISK" 40G

# Extract kernel/initrd from the ISO so we can pass 'autoinstall' on the
# kernel cmdline (skips the interactive confirmation prompt).
MNT=$(mktemp -d)
sudo mount -o loop,ro "$ISO" "$MNT"
cp "$MNT/casper/vmlinuz" "$MNT/casper/initrd" .
sudo umount "$MNT" && rmdir "$MNT"

exec qemu-system-x86_64 \
  -machine q35,accel=kvm -cpu host -smp 4 -m 4096 \
  -drive "file=$DISK,format=qcow2,if=virtio" \
  -drive "file=$ISO,media=cdrom" \
  -drive "file=$SEED,media=cdrom" \
  -kernel vmlinuz -initrd initrd \
  -append "autoinstall console=ttyS0" \
  -netdev user,id=n0,hostfwd=tcp::2222-:22 -device virtio-net-pci,netdev=n0 \
  -nographic
