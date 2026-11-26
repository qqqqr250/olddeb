#!/bin/bash
# Build an OldDeb ISO. Usage: ./scripts/build.sh [i386|amd64]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH="${1:-i386}"
DIST="${DIST:-bookworm}"
SNAPSHOT="${SNAPSHOT:-}"

case "$ARCH" in
    i386)  FLAVOUR="686" ;;
    amd64) FLAVOUR="amd64" ;;
    *)
        echo "usage: $0 [i386|amd64]" >&2
        exit 1
        ;;
esac

if [ "$(id -u)" -ne 0 ]; then
    exec sudo -E -- "$0" "$@"
fi

MIRROR="${MIRROR:-http://deb.debian.org/debian}"
SEC_MIRROR="${SEC_MIRROR:-http://security.debian.org/debian-security}"
if [ -n "$SNAPSHOT" ]; then
    MIRROR="http://snapshot.debian.org/archive/debian/$SNAPSHOT"
    SEC_MIRROR="http://snapshot.debian.org/archive/debian-security/$SNAPSHOT"
fi

# live-build is not reliable with spaces in the working path, so build in /var/tmp.
WORK="${WORK:-/var/tmp/olddeb-build}"
BUILD="$WORK/$ARCH"

command -v lb >/dev/null 2>&1 || {
    echo "ERROR: live-build is not installed. Run ./scripts/setup-host.sh first." >&2
    exit 1
}
command -v debootstrap >/dev/null 2>&1 || {
    echo "ERROR: debootstrap is not installed. Run ./scripts/setup-host.sh first." >&2
    exit 1
}

mkdir -p "$ROOT/out"
rm -rf "$BUILD"
mkdir -p "$BUILD/auto"
cp -a "$ROOT/config/." "$BUILD/config/"

# This live-build (3.0~a57) only executes hooks from config/hooks/*.chroot,
# while the project keeps them in the modern config/hooks/live/ layout.
mkdir -p "$BUILD/config/hooks"
cp "$ROOT"/config/hooks/live/*.chroot "$BUILD/config/hooks/"

# Ship the README inside the image.
mkdir -p "$BUILD/config/includes.chroot/usr/share/doc/olddeb"
cp "$ROOT/README.md" "$BUILD/config/includes.chroot/usr/share/doc/olddeb/README.md"

# Ubuntu's live-build expects Ubuntu's syslinux layout (/usr/lib/syslinux/),
# Debian 12 ships isolinux.bin in /usr/lib/ISOLINUX/ and modules in
# /usr/lib/syslinux/modules/bios/. Use our own splash-free theme (avoids the
# rsvg dependency) and copy the binaries in dereferenced.
BOOT="$BUILD/config/bootloaders/isolinux"
rm -rf "$BOOT"
cp -a "$ROOT/config/bootloaders/isolinux" "$BOOT"
cp -L /usr/lib/ISOLINUX/isolinux.bin "$BOOT/isolinux.bin"
for m in vesamenu.c32 menu.c32 ldlinux.c32 libcom32.c32 libutil.c32; do
    cp -L "/usr/lib/syslinux/modules/bios/$m" "$BOOT/$m"
done

# This Ubuntu live-build unconditionally unpacks an Ubuntu gfxboot "bootlogo"
# archive. An empty cpio archive satisfies that step for a plain text menu.
_tmp="$(mktemp -d)"
( cd "$_tmp" && ls -1 | cpio --quiet -o ) > "$BOOT/bootlogo"
rm -rf "$_tmp"

# Ubuntu's old live-build uses the pre-bookworm "bookworm/updates" security
# suite, so disable its automatic security repo and add the correct one.
mkdir -p "$BUILD/config/archives"
cat > "$BUILD/config/archives/olddeb-security.list.chroot" <<EOF
deb $SEC_MIRROR @DISTRIBUTION@-security @ARCHIVE_AREAS@
EOF

cat > "$BUILD/auto/config" <<EOF
#!/bin/sh
set -e
lb config noauto \\
    --distribution "$DIST" \\
    --architecture "$ARCH" \\
    --bootstrap debootstrap \\
    --binary-images iso-hybrid \\
    --bootloader syslinux \\
    --linux-flavours "$FLAVOUR" \\
    --archive-areas "main contrib non-free-firmware" \\
    --apt-recommends false \\
    --apt-indices false \\
    --apt-source-archives false \\
    --security false \\
    --debian-installer false \\
    --firmware-chroot false \\
    --firmware-binary false \\
    --memtest none \\
    --win32-loader false \\
    --initramfs live-boot \\
    --initsystem systemd \\
    --mirror-bootstrap "$MIRROR" \\
    --mirror-chroot "$MIRROR" \\
    --mirror-binary "$MIRROR" \\
    --mirror-chroot-security "$SEC_MIRROR" \\
    --mirror-binary-security "$SEC_MIRROR" \\
    --iso-application "OldDeb" \\
    --iso-preparer "OldDeb build" \\
    --iso-publisher "OldDeb" \\
    --iso-volume "OLDEB_12" \\
    --bootappend-live "components quiet loglevel=3 hostname=olddeb console=tty0 console=ttyS0,115200 persistence persistence-encryption=none" \\
    --checksums sha256 \\
    --compression xz
# lb_binary_syslinux labels the single-flavour entries with LB_LINUX_FLAVOUR.
echo 'LB_LINUX_FLAVOUR="$FLAVOUR"' >> config/chroot
EOF
chmod 0755 "$BUILD/auto/config"

echo "==> OldDeb $DIST / $ARCH"
echo "    mirror: $MIRROR"
echo "    build:  $BUILD"
echo

cd "$BUILD"
lb build

ISO="$(find "$BUILD" -maxdepth 1 \( -name '*.hybrid.iso' -o -name '*.iso' \) -print -quit)"
if [ -z "$ISO" ]; then
    echo "ERROR: build finished but no ISO was produced." >&2
    exit 1
fi

OUT="$ROOT/out/olddeb-${DIST}-${ARCH}-cli.iso"
install -m 0644 "$ISO" "$OUT"
sha256sum "$OUT" > "$OUT.sha256"

PKG="$(find "$BUILD" -maxdepth 1 -name 'live-image-*.packages' -print -quit || true)"
if [ -n "$PKG" ]; then
    cp "$PKG" "$ROOT/out/olddeb-${DIST}-${ARCH}-packages.txt"
fi

echo
echo "==> Done: $OUT"
ls -lh "$OUT"
