#!/bin/bash
set -e

# --- 1. ENVIRONMENT & DIRECTORIES ---
ROOT=$(pwd)/axiom_rootfs
ISO_DIR=$(pwd)/axiom_iso
mkdir -p "$ROOT" "$ISO_DIR/live" output
export DEBIAN_FRONTEND=noninteractive

echo "--- Phase 1: Bootstrapping Base System ---"
sudo debootstrap --arch amd64 jammy "$ROOT" http://archive.ubuntu.com/ubuntu/

# Mount virtual filesystems (Required for Kernel Installation)
sudo mount --bind /dev "$ROOT/dev"
sudo mount --bind /run "$ROOT/run"
sudo mount -t proc proc "$ROOT/proc"
sudo mount -t sysfs sys "$ROOT/sys"

# --- Phase 2: Chroot Operations ---
sudo chroot "$ROOT" /bin/bash <<EOF
export DEBIAN_FRONTEND=noninteractive

# Configure Repositories
cat <<EOT > /etc/apt/sources.list
deb http://archive.ubuntu.com/ubuntu/ jammy main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ jammy-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ jammy-security main restricted universe multiverse
EOT

apt-get update

echo "--- Phase 2a: Critical Boot Files ---"
# Installing the kernel immediately ensures /boot is populated early
apt-get install -y --no-install-recommends \
    linux-image-generic initramfs-tools casper wget curl ca-certificates gnupg2

echo "--- Phase 2b: UI & Android-Style Engine ---"
# Installing KDE Plasma and Axiom dependencies
apt-get install -y --no-install-recommends \
    sddm plasma-desktop plasma-nm network-manager kde-cli-tools \
    ubiquity ubiquity-frontend-gtk yad imagemagick \
    zram-config maliit-keyboard qtwayland5 iio-sensor-proxy

# Install Chrome Engine
wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
apt-get install -y ./google-chrome-stable_current_amd64.deb || apt-get install -f -y
rm google-chrome-stable_current_amd64.deb

# --- AXIOM ENGINE CONFIG ---
mkdir -p /usr/local/bin

# The Interface Style Toggle
cat <<'MODE_EOT' > /usr/local/bin/axiom-mode-toggle
#!/bin/bash
MSG="Welcome to Axiom OS.\n\nChoose the interface style that fits your workflow.\n\n<b>Note:</b> You can change this later in <b>Settings > Hardware > Interface Style</b>."

MODE=\$(yad --title="Axiom Initial Setup" --window-icon="preferences-desktop-display" \
    --text="\$MSG" --text-align=center --width=480 \
    --button="Laptop Style:0" --button="Tablet Style (Android):2")

if [ \$? -eq 0 ]; then
    # Laptop: Standard Taskbar
    kwriteconfig5 --file plasma-org.kde.plasma.desktop-appletsrc --group Panels --group 1 --key Thickness 40
    kwriteconfig5 --file plasma-org.kde.plasma.desktop-appletsrc --group Applets --group 2 --key plugin "org.kde.plasma.taskmanager"
else
    # Tablet: Android-style thick icon dock + Recents gesture
    kwriteconfig5 --file plasma-org.kde.plasma.desktop-appletsrc --group Panels --group 1 --key Thickness 80
    kwriteconfig5 --file plasma-org.kde.plasma.desktop-appletsrc --group Applets --group 1 --key plugin "org.kde.plasma.kicker"
    kwriteconfig5 --file plasma-org.kde.plasma.desktop-appletsrc --group Applets --group 2 --key plugin "org.kde.plasma.icontasks"
    kwriteconfig5 --file kwinrc --group Effect-PresentWindows --key BorderActivate 7
fi

# Enable On-Screen Keyboard (Maliit) for both modes
kwriteconfig5 --file kwinrc --group Wayland --key InputMethod "/usr/share/applications/com.github.maliit.keyboard.desktop"

busctl --user call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell refreshCurrentShell
MODE_EOT
chmod +x /usr/local/bin/axiom-mode-toggle

# Setup Autostart and Settings Desktop Entry
mkdir -p /etc/skel/.config/autostart
echo -e "[Desktop Entry]\nType=Application\nExec=bash -c 'axiom-mode-toggle && rm ~/.config/autostart/axiom-welcome.desktop'\nName=Axiom Welcome" > /etc/skel/.config/autostart/axiom-welcome.desktop

echo -e "[Desktop Entry]\nName=Interface Style\nExec=axiom-mode-toggle\nIcon=preferences-desktop-display\nType=Application\nCategories=Settings;X-KDE-settings-hardware;" > /usr/share/applications/axiom-mode.desktop

# Performance: Enable ZRAM
echo 'ALGO=lz4' > /etc/default/zramswap
echo 'PERCENT=60' >> /etc/default/zramswap

# Final cleanup inside chroot
apt-get clean
EOF

# --- Phase 3: Packaging & Verification ---
echo "--- Phase 3: Verifying and Copying Kernel ---"

# Use find to locate the exact filenames created by the installation
VMLINUZ=\$(find "$ROOT/boot" -name "vmlinuz-*-generic" | head -n 1)
INITRD=\$(find "$ROOT/boot" -name "initrd.img-*-generic" | head -n 1)

if [ -z "\$VMLINUZ" ] || [ -z "\$INITRD" ]; then
    echo "ERROR: Kernel or Initrd not found in $ROOT/boot/"
    ls -R "$ROOT/boot"
    exit 1
fi

sudo cp -v "\$VMLINUZ" "$ISO_DIR/live/vmlinuz"
sudo cp -v "\$INITRD" "$ISO_DIR/live/initrd"

# Cleanup mounts
sudo umount -l "$ROOT/dev" "$ROOT/run" "$ROOT/proc" "$ROOT/sys" || true

echo "--- Phase 4: Compressing Axiom OS ISO ---"
sudo mksquashfs "$ROOT" output/AxiomOS.iso -comp xz
