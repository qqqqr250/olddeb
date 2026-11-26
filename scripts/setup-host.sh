#!/bin/bash
# Install the host packages needed to build and test OldDeb.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    exec sudo -- "$0" "$@"
fi

apt-get update
apt-get install -y --no-install-recommends \
    live-build debootstrap squashfs-tools \
    xorriso genisoimage isolinux syslinux-utils syslinux-common \
    grub-pc-bin grub-efi-amd64-bin mtools dosfstools parted e2fsprogs \
    qemu-system-x86 zstd rsync whiptail debian-archive-keyring

echo
echo "live-build version:"
lb --version || true
