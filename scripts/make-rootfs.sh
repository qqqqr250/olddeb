#!/bin/bash
# Export a completed build as a rootfs tarball. Usage: ./scripts/make-rootfs.sh [i386|amd64]
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
OUT="$ROOT/out/olddeb-12-$ARCH-rootfs.tar.zst"

echo "==> Packing $CHROOT"
tar -C "$CHROOT" --xattrs --acls --numeric-owner \
    --exclude=./proc/* --exclude=./sys/* --exclude=./dev/* --exclude=./run/* \
    --exclude=./tmp/* --exclude=./var/tmp/* --exclude=./mnt/* --exclude=./media/* \
    --exclude=./etc/ssh/ssh_host_* \
    -cf - . | zstd -19 -T0 -f -o "$OUT"

sha256sum "$OUT" > "$OUT.sha256"
ls -lh "$OUT"
