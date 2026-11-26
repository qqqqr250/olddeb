# OldDeb — Debian 12 based CLI distribution for old hardware

A small, reproducible Debian 12 ("bookworm") derivative for old PCs. CLI only:
no Xorg, no desktop, no GPU firmware. Built with Debian's `live-build`.

## What you get

| Artifact | Purpose |
|---|---|
| `out/olddeb-12-<arch>-cli.iso` | Hybrid BIOS live ISO, optional persistence, includes the installer |
| `out/olddeb-12-<arch>.img.zst` | Raw disk image for CF/SD/IDE DOM/SSD (`dd` it) |
| `out/olddeb-12-<arch>-rootfs.tar.zst` | Root filesystem tarball (PXE, containers, manual deploy) |

Two architectures:

- `i386` — 32-bit, Debian's last bootable 32-bit port. Needs an i686-class CPU
  (Pentium Pro/II or newer). Kernel: `linux-image-686` (non-PAE).
- `amd64` — 64-bit. Kernel: `linux-image-amd64`.

## Requirements

Build host: Debian/Ubuntu/Mint, ~2 GB free disk, root access.

```sh
sudo apt install live-build debootstrap squashfs-tools xorriso isolinux \
  syslinux-utils grub-pc-bin grub-efi-amd64-bin mtools dosfstools \
  qemu-system-x86 zstd rsync whiptail debian-archive-keyring
```

or just:

```sh
./scripts/setup-host.sh
```

## Build

```sh
./scripts/build.sh i386      # or amd64
```

The script re-executes itself with `sudo` (debootstrap needs root). It takes
about 10–30 minutes and writes artifacts to `out/`.

Reproducible builds against the Debian snapshot archive:

```sh
SNAPSHOT=20261101T000000Z ./scripts/build.sh i386
```

## Test in QEMU

```sh
./scripts/test-qemu.sh i386            # 256 MB RAM, pentium3 CPU
./scripts/test-qemu.sh amd64 512       # 512 MB RAM
```

Add a second disk for persistence testing:

```sh
./scripts/test-qemu.sh i386 256 --persistence
```

## Verification (prebuilt artifacts)

Each artifact in `out/` was booted in QEMU (KVM, BIOS):

| Test | Result |
|---|---|
| `i386` ISO, 256 MB RAM | login, DHCP/DNS, zram/earlyoom active, passwordless sudo |
| `i386` raw image | GRUB boots from disk, root on UUID, `sudo` asks for password |
| `i386` persistence | file written to `/root` survived a reboot (partitioned and whole-disk layouts) |
| `amd64` ISO, 512 MB RAM | login, DHCP/DNS, zram/earlyoom active, passwordless sudo |
| `amd64` raw image | GRUB boots from disk, root on UUID, `sudo` asks for password |
| i386 ISO via Ventoy 1.1.18 | detected in the Ventoy menu, boots in normal mode (BIOS) |

Serial-console logs are in [`verification/`](verification/) (also copied to
`out/verification/` by the build). `out/SHA256SUMS` and `out/MANIFEST.txt` list
the released files.

## Install to a real disk

Boot the ISO (CD-RW is the safest bet on old BIOSes; use Plop Boot Manager if
the machine refuses to boot USB), log in as `user` / `live`, then:

```sh
sudo install-to-disk
```

It partitions the selected disk (MBR, one ext4 root), copies the live system,
sets the hostname/password, and installs GRUB. **All data on the target disk is
erased.**

## Persistence on a USB stick

After writing the ISO with `dd`, create a second partition:

```sh
sudo parted /dev/sdX mkpart primary ext4 <start> 100%
sudo mkfs.ext4 -L persistence /dev/sdX2
sudo mount /dev/sdX2 /mnt
echo "/ union" | sudo tee /mnt/persistence.conf
sudo umount /mnt
```

The live boot command line already contains `persistence`, so changes under `/`
survive reboots. Without the partition, the ISO behaves as a normal live system.

## Ventoy

The ISO works with [Ventoy](https://www.ventoy.net/) on **BIOS** machines (tested
with Ventoy 1.1.18, "Boot in normal mode"). Copy the ISO to the Ventoy data
partition and pick it from the Ventoy menu.

- **UEFI and Secure Boot are not supported**: the ISO has no EFI bootloader
  (BIOS-only by design). Ventoy on a UEFI system will not boot it.
- **Persistence**: Ventoy's built-in `.dat` persistence is for casper-based
  distros and is ignored by `live-boot`. Instead, reserve space when installing
  Ventoy (`Ventoy2Disk.sh -i /dev/sdX -r 1024`), format that space ext4 with
  label `persistence`, and put `/ union` in `persistence.conf` (see above).
  OldDeb's default command line has `persistence`, so it is picked up
  automatically.

## Raw disk image

```sh
./scripts/make-disk-image.sh i386            # sized from the rootfs + 512 MB
SIZE=2G ./scripts/make-disk-image.sh i386
```

Writes `out/olddeb-12-i386.img.zst`. Decompress and `dd` to the target device:

```sh
zstd -d out/olddeb-12-i386.img.zst -o /tmp/olddeb.img
sudo dd if=/tmp/olddeb.img of=/dev/sdX bs=4M status=progress conv=fsync
```

## Rootfs tarball

```sh
./scripts/make-rootfs.sh i386
```

## Layout

```
config/
  package-lists/olddeb.list.chroot   # package set
  hooks/live/*.chroot                # chroot-time configuration
  includes.chroot/                   # files copied into the image
    usr/local/sbin/install-to-disk
    usr/local/sbin/wifi-connect
    etc/dhcpcd.conf                  # DHCP + DNS defaults
    etc/systemd/system/dhcpcd.service
scripts/
  build.sh          # build ISO for one architecture
  test-qemu.sh      # boot the ISO in QEMU
  make-disk-image.sh
  make-rootfs.sh
  probe.sh          # hardware inventory for target machines
  setup-host.sh     # install build dependencies
```

## Defaults

- Hostname: `olddeb` (live boot param `hostname=olddeb`)
- Live user: `user` / `live`, passwordless sudo, autologin on tty1
- Disk image: `user` / `live`, `sudo` asks for the password, no autologin
- Boot menu: Live, failsafe, and serial-console (`ttyS0,115200`) entries
- SSH server installed but **disabled**; `sudo systemctl start ssh` to use it
- Networking: `dhcpcd` (DHCP + DNS on all wired/wireless interfaces)
- Wi-Fi: `sudo wifi-connect "SSID" "password"`
- Low RAM: zram (50% of RAM, zstd), `earlyoom`, journald in volatile mode
- Locale: `en_US.UTF-8`, timezone UTC, keymap `us`
- Boot console: `tty0` + `ttyS0,115200`

## Hardware floor

- Debian 12 i386 requires i686 (Pentium Pro/II+). 486/Pentium I are **not**
  supported by this base.
- Some packages (browsers, Rust/LLVM-built tools) need SSE2. The base system and
  CLI tools do not.
- Non-PAE CPUs (Pentium M, early Core) are supported by `linux-image-686`.
  RAM above 4 GB needs the PAE variant (`linux-image-686-pae`), not built here.

## Lifetime

Debian 12 LTS ends in **June 2028**. Snapshot-pinned builds keep rebuilding
after that, but security updates stop. Plan an exit (frozen tree with own repo,
Devuan, or Alpine x86 for CLI) before then.

## Known limitations (v1)

- BIOS boot only (`syslinux`). UEFI support needs Debian's newer live-build or
  a post-processing step; old target hardware is BIOS, so this is intentional.
- No graphical environment by design.
- Wi-Fi needs manual `wifi-connect`; no NetworkManager.
- The installer is a simple clone installer, not a full disk encryption /
  LVM / dual-boot setup.
- In the prebuilt i386 image the shell prompt may show a `(live)` prefix
  (`/etc/debian_chroot` left over from the interrupted build); harmless.
- The prebuilt ISO's motd suggests `zramctl`, which lives in `/usr/sbin`
  (not in a normal user's `PATH`): use `sudo zramctl`. Fixed in
  `config/hooks/live/0200-branding.chroot` for the next build.
