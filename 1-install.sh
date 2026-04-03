#!/bin/bash

#
# Arch Linux + Full Disk Encryption + BTRFS + Rollback Installation Script
# ==========================================================================
# ==========================================================================
# Installation parameters
# ==========================================================================

# OS:           Arch Linux, rolling release
# CPU:          Intel (intel-ucode)
# FS:           BTRFS with CoW, zstd compression, noatime
# Bootloader:   GRUB with grub-btrfs + inotify-tools
# Init:         systemd
# Keymap:       de-latin1-nodeadkeys
# Timezone:     Europe/Berlin
# Locale:       en_GB.UTF-8

# =============================================================================
# Disk layout  (target: /dev/nvme0n1)
# =============================================================================

# p1   ESP        1024 MiB   FAT32           /boot/efi
# p2   swap       100 GiB    LUKS2 → swap    /dev/mapper/cryptswap
# p3   root       remainder  LUKS2 → BTRFS   /dev/mapper/cryptroot

# =============================================================================
# BTRFS subvolume layout
# =============================================================================

# @                   →  /
# @home               →  /home
# @snapshots          →  /.snapshots
# @log                →  /var/log
# @cache              →  /var/cache
# @tmp                →  /var/tmp
# @grub               →  /boot/grub        (protected from rollback)

# =============================================================================
# /boot lives on BTRFS @ — kernel is snapshotable
# /boot/efi is the ESP — FAT32, mounted over BTRFS
# =============================================================================

# =============================================================================
# Encryption
# =============================================================================

# Both partitions encrypted with LUKS2
# Root unlocked by passphrase at boot
# Swap unlocked by keyfile embedded in initramfs
# → one passphrase prompt, both volumes open


# =============================================================================
# Snapshots
# =============================================================================

# Tool:         snapper
# root config:  / — timeline + snap-pac (pre/post on pacman)
# home config:  /home — timeline only
# grub-btrfs:   watches /.snapshots, regenerates grub.cfg
# snap-pac:     hooks into pacman, auto pre/post snapshots


# =============================================================================
# fstab strategy
# =============================================================================

# / root entry:   NO subvol= — mounts BTRFS default subvolume
#                 snapper rollback works correctly
# All others:     explicit subvol= — immune to rollbacks

# =============================================================================
# initramfs hooks (mkinitcpio)
# =============================================================================

# base systemd autodetect microcode modconf kms
# keyboard sd-vconsole block sd-encrypt filesystems fsck

# =============================================================================
# Swap + hibernation
# =============================================================================

# resume= points at /dev/mapper/cryptswap
# rd.luks.name for both p2 and p3 in kernel cmdline

# =============================================================================

set -euo pipefail

# =============================================================================
# CONFIGURATION — Review and adjust these before running anything
# =============================================================================

DISK="/dev/nvme0n1"           # Target disk — use 'lsblk' to identify
HOSTNAME="t480s"              # Machine hostname
USERNAME="user"               # Non-root user to create
TIMEZONE="Europe/Berlin"      # timedatectl list-timezones
LOCALE="en_GB.UTF-8"          # Locale
KEYMAP="de-latin1-nodeadkeys" # Console keymap (loadkeys)

# NVMe partition naming uses a 'p' separator (e.g., /dev/nvme0n1p1)
# For SATA/USB drives it would be /dev/sdX1, /dev/sdX2 (no 'p')
PART_EFI="${DISK}p1"          # EFI System Partition
PART_ROOT="${DISK}p2"         # LUKS partition (will hold root)
CRYPT_NAME="cryptdev"         # dm-crypt mapped device name
