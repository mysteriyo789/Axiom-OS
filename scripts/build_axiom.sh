#!/usr/bin/env bash
set -xeu pipefail

# --------------------------------------------------
# Environment Variables & Paths
# --------------------------------------------------
WORK_DIR="$(pwd)/build_work"
CHROOT_DIR="${WORK_DIR}/chroot"
ISO_DIR="${WORK_DIR}/iso"
OUTPUT_DIR="$(pwd)/output"
RELEASE="jammy"
ARCH="amd64"

mkdir -p "${CHROOT_DIR}" "${ISO_DIR}" "${OUTPUT_DIR}"

# --------------------------------------------------
# 1. Bootstrap Minimal Ubuntu System
# --------------------------------------------------
if [ ! -f "${CHROOT_DIR}/usr/bin/apt-get" ]; then
    debootstrap --arch="${ARCH}" --variant=minbase "${RELEASE}" "${CHROOT_DIR}" http://archive.ubuntu.com/ubuntu/
fi

# Mount essential virtual filesystems for chroot execution
mount -t proc /proc "${CHROOT_DIR}/proc"
mount -t sysfs /sys "${CHROOT_DIR}/sys"
mount --bind /dev "${CHROOT_DIR}/dev"
mount --bind /dev/pts "${CHROOT_DIR}/dev/pts"

cleanup() {
    umount -l "${CHROOT_DIR}/dev/pts" || true
    umount -l "${CHROOT_DIR}/dev" || true
    umount -l "${CHROOT_DIR}/sys" || true
    umount -l "${CHROOT_DIR}/proc" || true
}
trap cleanup EXIT

# --------------------------------------------------
# 2. Configure Repositories & Install Core Packages
# --------------------------------------------------
cat <<'EOF' > "${CHROOT_DIR}/etc/apt/sources.list"
deb http://archive.ubuntu.com/ubuntu/ jammy main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ jammy-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ jammy-security main restricted universe multiverse
EOF

chroot "${CHROOT_DIR}" /bin/bash -s <<'CHROOT_ENV'
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
    linux-image-generic \
    live-boot \
    casper \
    initramfs-tools \
    systemd-sysv \
    network-manager \
    kde-plasma-desktop \
    wireguard \
    btrfs-progs \
    snapper \
    sudo

# Add early kernel modules to fix Ventoy loopback mounting
cat <<'MODULES_EOT' >> /etc/initramfs-tools/modules
loop
overlay
iso9660
squashfs
uas
usb_storage
MODULES_EOT

# Rebuild initramfs with loopback drivers embedded
update-initramfs -u -k all
CHROOT_ENV

# --------------------------------------------------
# 3. Assemble ISO Structure
# --------------------------------------------------
mkdir -p "${ISO_DIR}/live"
mkdir -p "${ISO_DIR}/boot/grub"

# Copy Kernel and initrd into ISO structure
cp "${CHROOT_DIR}/boot/vmlinuz-"* "${ISO_DIR}/live/vmlinuz"
cp "${CHROOT_DIR}/boot/initrd.img-"* "${ISO_DIR}/live/initrd"

# Compress Root Filesystem into SquashFS
mksquashfs "${CHROOT_DIR}" "${ISO_DIR}/live/filesystem.squashfs" -comp xz -noappend

# Calculate filesystem size for casper
printf $(du -sx --block-size=1 "${CHROOT_DIR}" | cut -f1) > "${ISO_DIR}/live/filesystem.size"

# --------------------------------------------------
# 4. Generate Ventoy-Compatible GRUB Configuration
# --------------------------------------------------
cat <<'GRUB_EOT' > "${ISO_DIR}/boot/grub/grub.cfg"
set default=0
set timeout=3

menuentry "Axiom OS (Live x64 UEFI/BIOS)" {
    linux /live/vmlinuz boot=casper iso-scan/filename=${iso_path} ignore_uuid quiet splash toram ---
    initrd /live/initrd
}
GRUB_EOT

# --------------------------------------------------
# 5. Build Hybrid UEFI/BIOS Bootable ISO Image
# --------------------------------------------------
grub-mkrescue -o "${OUTPUT_DIR}/AxiomOS.iso" "${ISO_DIR}" -- -volid "AXIOM_OS"

echo "ISO Build Complete: ${OUTPUT_DIR}/AxiomOS.iso"
