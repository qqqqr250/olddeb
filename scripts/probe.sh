#!/bin/bash
# Collect hardware information on a target machine. Run from any live Linux.
set -uo pipefail

OUT="probe-$(hostname -s 2>/dev/null || echo unknown)-$(date +%Y%m%d-%H%M%S).txt"

{
    echo "=== date ==="
    date -Is
    echo
    echo "=== uname ==="
    uname -a
    echo
    echo "=== os-release ==="
    cat /etc/os-release 2>/dev/null
    echo
    echo "=== cpu ==="
    lscpu 2>/dev/null || cat /proc/cpuinfo
    echo
    echo "=== cpu flags ==="
    grep -m1 '^flags' /proc/cpuinfo
    echo
    echo "=== memory ==="
    free -m
    grep -E 'MemTotal|SwapTotal' /proc/meminfo
    echo
    echo "=== boot mode ==="
    if [ -d /sys/firmware/efi ]; then echo UEFI; else echo BIOS; fi
    echo
    echo "=== dmi ==="
    for f in sys_vendor product_name board_name bios_version; do
        p="/sys/class/dmi/id/$f"
        [ -r "$p" ] && echo "$f: $(cat "$p")"
    done
    echo
    echo "=== disks ==="
    lsblk -o NAME,SIZE,TYPE,MODEL,TRAN,ROTA 2>/dev/null
    echo
    echo "=== pci ==="
    lspci -nn 2>/dev/null
    echo
    echo "=== usb ==="
    lsusb 2>/dev/null
    echo
    echo "=== network ==="
    ip -br link 2>/dev/null
    ip -br address 2>/dev/null
    rfkill list 2>/dev/null
    echo
    echo "=== power ==="
    for b in /sys/class/power_supply/*; do
        [ -e "$b/type" ] && echo "$b: $(cat "$b/type")"
    done
    echo
    echo "=== kernel messages (errors/firmware) ==="
    dmesg 2>/dev/null | grep -iE 'error|fail|firmware|not found' | tail -50
} | tee "$OUT"

echo
echo "Saved to $OUT"
