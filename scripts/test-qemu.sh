#!/bin/bash
# Boot an OldDeb ISO in QEMU. Usage: ./scripts/test-qemu.sh [i386|amd64] [RAM_MB] [--persistence]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH="${1:-i386}"
RAM="${2:-256}"
MODE="${3:-}"

case "$ARCH" in
    i386)  QEMU="qemu-system-i386";  CPU="pentium3" ;;
    amd64) QEMU="qemu-system-x86_64"; CPU="core2duo" ;;
    *)
        echo "usage: $0 [i386|amd64] [RAM_MB] [--persistence]" >&2
        exit 1
        ;;
esac

ISO="$ROOT/out/olddeb-12-$ARCH-cli.iso"
[ -f "$ISO" ] || {
    echo "ERROR: $ISO not found. Build it first: ./scripts/build.sh $ARCH" >&2
    exit 1
}

command -v "$QEMU" >/dev/null 2>&1 || {
    echo "ERROR: $QEMU not found. Run ./scripts/setup-host.sh first." >&2
    exit 1
}

ARGS=(-m "$RAM" -cpu "$CPU" -cdrom "$ISO" -boot d -nic user,model=e1000 -vga std)

if [ "$MODE" = "--persistence" ]; then
    IMG="$ROOT/build/persistence-$ARCH.img"
    mkdir -p "$ROOT/build"
    if [ ! -f "$IMG" ]; then
        echo "Creating 512M persistence disk at $IMG"
        TMP="$(mktemp -d)"
        printf '/ union\n' > "$TMP/persistence.conf"
        truncate -s 512M "$IMG"
        mke2fs -q -t ext4 -F -L persistence -d "$TMP" "$IMG"
        rm -rf "$TMP"
    fi
    ARGS+=(-drive "file=$IMG,format=raw,if=ide")
fi

if [ "${SERIAL:-0}" = "1" ]; then
    exec "$QEMU" "${ARGS[@]}" -display none -serial mon:stdio
else
    exec "$QEMU" "${ARGS[@]}"
fi
