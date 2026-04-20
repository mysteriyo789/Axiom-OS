#!/bin/bash
set -e

# --- 1. SETUP ---
ROOT=$(pwd)/axiom_rootfs
ISO_DIR=$(pwd)/axiom_iso
mkdir -p "$ROOT" "$ISO_DIR/live" output
export DEBIAN_FRONTEND=noninteractive

echo "--- Phase 1: Minimal Bootstrap ---"
sudo debootstrap --arch amd64 --variant=minbase jammy "$ROOT" http://archive.ubuntu.com/ubuntu/

# --- 2. MOUNTING ---
sudo mount --bind /dev "$ROOT/dev"
sudo mount --bind /run "$ROOT/run"
sudo mount -t proc proc "$ROOT/proc"
sudo mount -t sysfs sysfs "$ROOT/sys"

# --- 3. CHROOT LOGIC ---
sudo chroot "$ROOT" /bin/bash <<'EOF'
export DEBIAN_FRONTEND=noninteractive

# CRITICAL FIX: Enable Universe and Multiverse repositories
cat <<EOT > /etc/apt/sources.list
deb http://archive.ubuntu.com/ubuntu/ jammy main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ jammy-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ jammy-security main restricted universe multiverse
EOT

# Optimization: Skip docs
echo 'path-exclude /usr/share/doc/*' > /etc/dpkg/dpkg.cfg.d/01_nodoc
echo 'path-exclude /usr/share/man/*' >> /etc/dpkg/dpkg.cfg.d/01_nodoc

apt-get update

echo "--- Installing Tools & Kernel ---"
# We install wget and gnupg first so the rest of the script can use them
apt-get install -y --no-install-recommends wget ca-certificates gnupg2
apt-get install -y --no-install-recommends linux-image-generic initramfs-tools casper

echo "--- Installing Axiom UI Components ---"
apt-get install -y --no-install-recommends \
    sddm plasma-desktop-data plasma-workspace plasma-nm \
    network-manager kde-cli-tools ubiquity ubiquity-frontend-gtk \
    yad imagemagick zram-config maliit-keyboard qtwayland5 iio-sensor-proxy

echo "--- Integrating App Hub Runtime ---"
wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
apt-get install -y ./google-chrome-stable_current_amd64.deb || apt-get install -f -y
rm google-chrome-stable_current_amd64.deb

# --- AXIOM CUSTOMIZATIONS ---
mkdir -p /usr/local/bin

cat <<'HUB_EOT' > /usr/local/bin/axiom-app-hub
#!/bin/bash
google-chrome --app="https://apphub.axiom-os.co" --class="AppHub" --no-first-run --force-dark-mode
HUB_EOT
chmod +x /usr/local/bin/axiom-app-hub

mkdir -p /usr/share/applications
cat <<ENTRY_EOT > /usr/share/applications/app-hub.desktop
[Desktop Entry]
Name=App Hub
GenericName=Software Store
Exec=/usr/local/bin/axiom-app-hub
Icon=system-software-install
Type=Application
Categories=System;Network;
StartupWMClass=AppHub
ENTRY_EOT

cat <<'MODE_EOT' > /usr/local/bin/axiom-mode-toggle
#!/bin/bash
MODE=$(yad --title="Axiom OS" --text="Select Interface Style" --button="Laptop:0" --button="Tablet:2" --width=400)
if [ $? -eq 0 ]; then
    kwriteconfig5 --file plasma-org.kde.plasma.desktop-appletsrc --group Panels --group 1 --key Thickness 40
else
    kwriteconfig5 --file plasma-org.kde.plasma.desktop-appletsrc --group Panels --group 1 --key Thickness 80
fi
busctl --user call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell refreshCurrentShell
MODE_EOT
chmod +x /usr/local/bin/axiom-mode-toggle

apt-get clean
rm -rf /var/lib/apt/lists/*
EOF

# --- 4. KERNEL RECOVERY ---
VMLINUZ=$(find "$ROOT/boot" -name "vmlinuz-*-generic" | head -n 1)
INITRD=$(find "$ROOT/boot" -name "initrd.img-*-generic" | head -n 1)

sudo cp -v "$VMLINUZ" "$ISO_DIR/live/vmlinuz"
sudo cp -v "$INITRD" "$ISO_DIR/live/initrd"

# Unmount
sudo umount -l "$ROOT/sys" "$ROOT/proc" "$ROOT/run" "$ROOT/dev"

# --- 5. ISO BUILD ---
sudo mksquashfs "$ROOT" output/AxiomOS.iso -comp gzip -no-progress
