#!/bin/bash
# Build a raw BIOS disk image from a completed build. Usage: [SIZE=2G] ./scripts/make-disk-image.sh [i386|amd64]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH="${1:-i386}"
WORK="${WORK:-/var/tmp/olddeb-build}"

if [ "$(id -u)" -ne 0 ]; then
    exec sudo -E -- "$0" "$@"
fi

CHROOT="$WORK/$ARCH/chroot"
[ -d "$CHROOT" ] || {
    echo "ERROR: $CHROOT not found. Build first: ./scripts/build.sh $ARCH" >&2
    exit 1
}

mkdir -p "$ROOT/out"
MNT=""
LOOP=""

cleanup() {
    set +e
    if [ -n "$MNT" ] && mountpoint -q "$MNT" 2>/dev/null; then
        for d in dev proc sys run; do
            umount "$MNT/$d" 2>/dev/null
        done
        umount -R "$MNT" 2>/dev/null
    fi
    [ -n "$MNT" ] && rmdir "$MNT" 2>/dev/null
    [ -n "$LOOP" ] && losetup -d "$LOOP" 2>/dev/null
    return 0
}
trap cleanup EXIT

USED_MB="$(du -sm "$CHROOT" | cut -f1)"
SIZE="${SIZE:-$((USED_MB + 512))M}"

IMG="$ROOT/out/olddeb-12-$ARCH.img"
rm -f "$IMG" "$IMG.zst" "$IMG.zst.sha256"

echo "==> Creating $SIZE image ($USED_MB MB used in chroot)"
truncate -s "$SIZE" "$IMG"
parted -s "$IMG" mklabel msdos
parted -s "$IMG" mkpart primary ext4 2MiB 100%
parted -s "$IMG" set 1 boot on

LOOP="$(losetup --find --show -P "$IMG")"
PART="${LOOP}p1"
mkfs.ext4 -F -L olddeb "$PART" >/dev/null

MNT="$(mktemp -d)"
mount "$PART" "$MNT"

echo "==> Copying root filesystem"
rsync -aHAX --numeric-ids \
    --exclude=/proc/* --exclude=/sys/* --exclude=/dev/* --exclude=/run/* \
    --exclude=/tmp/* --exclude=/var/tmp/* --exclude=/mnt/* --exclude=/media/* \
    "$CHROOT/" "$MNT/"

ROOT_UUID="$(blkid -s UUID -o value "$PART")"
cat > "$MNT/etc/fstab" <<EOF
UUID=$ROOT_UUID  /  ext4  errors=remount-ro  0  1
EOF

echo olddeb > "$MNT/etc/hostname"
cat > "$MNT/etc/hosts" <<'EOF'
127.0.0.1 localhost
127.0.1.1 olddeb
::1 localhost ip6-localhost ip6-loopback
EOF

rm -f "$MNT/etc/machine-id"
touch "$MNT/etc/machine-id"

# The disk image is not a live session: require the password for sudo and do
# not auto-login. Credentials are user / live (see README).
rm -f "$MNT/etc/sudoers.d/olddeb-live"
rm -f "$MNT/etc/systemd/system/getty@tty1.service.d/autologin.conf"
rmdir "$MNT/etc/systemd/system/getty@tty1.service.d" 2>/dev/null || true

for d in dev proc sys run; do
    mkdir -p "$MNT/$d"
    mount --bind "/$d" "$MNT/$d"
done

# Host keys for the image (needs /dev/urandom).
rm -f "$MNT"/etc/ssh/ssh_host_* 2>/dev/null || true
chroot "$MNT" ssh-keygen -A >/dev/null 2>&1 || true

cat > "$MNT/etc/default/grub" <<'EOF'
GRUB_DEFAULT=0
GRUB_TIMEOUT=3
GRUB_DISTRIBUTOR="OldDeb"
GRUB_CMDLINE_LINUX_DEFAULT="quiet console=tty0 console=ttyS0,115200"
GRUB_CMDLINE_LINUX=""
GRUB_DISABLE_OS_PROBER=true
EOF

echo "==> Installing GRUB"
chroot "$MNT" grub-install --target=i386-pc --recheck "$LOOP" >/dev/null
chroot "$MNT" update-grub >/dev/null

sync
cleanup
trap - EXIT

echo "==> Compressing"
zstd -19 -T0 -f "$IMG" -o "$IMG.zst"
rm -f "$IMG"
sha256sum "$IMG.zst" > "$IMG.zst.sha256"

ls -lh "$IMG.zst"
