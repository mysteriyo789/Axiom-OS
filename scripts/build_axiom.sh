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

# Optimization: Shrink footprint
echo 'path-exclude /usr/share/doc/*' > /etc/dpkg/dpkg.cfg.d/01_nodoc
echo 'path-exclude /usr/share/man/*' >> /etc/dpkg/dpkg.cfg.d/01_nodoc

apt-get update
apt-get install -y --no-install-recommends \
    linux-image-generic initramfs-tools casper wget curl ca-certificates \
    sddm plasma-desktop-data plasma-workspace plasma-nm network-manager \
    yad zram-config maliit-keyboard iio-sensor-proxy

# Install the Axiom Runtime Engine
wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
apt-get install -y ./google-chrome-stable_current_amd64.deb || apt-get install -f -y
rm google-chrome-stable_current_amd64.deb

# --- AXIOM APP HUB: INVISIBLE INTEGRATION ---

# 1. Create the App Hub PWA Wrapper
cat <<'HUB_EOT' > /usr/local/bin/axiom-app-hub
#!/bin/bash
# Launching the App Hub as a clean, native-feel standalone app
# (This points to the internal Axiom-PWA gateway URL)
google-chrome --app="https://apphub.axiom-os.co" \
              --class="AppHub" \
              --no-first-run \
              --enable-features=WebUIDarkMode,RunAllFlashInAllowMode \
              --force-dark-mode \
              --user-data-dir="/home/\$USER/.config/axiom-hub"
HUB_EOT
chmod +x /usr/local/bin/axiom-app-hub

# 2. Updated System Menu Registration (Strictly "Software Store" Branding)
cat <<ENTRY_EOT > /usr/share/applications/app-hub.desktop
[Desktop Entry]
Name=App Hub
GenericName=Software Store
Comment=Access all software optimized for Axiom OS
Exec=/usr/local/bin/axiom-app-hub
Icon=system-software-install
Type=Application
Categories=System;Network;
StartupWMClass=AppHub
ENTRY_EOT

# 3. Axiom Setup (Simplified Welcome Message)
cat <<'MODE_EOT' > /usr/local/bin/axiom-mode-toggle
#!/bin/bash
MSG="<b>Welcome to Axiom OS.</b>\n\nYour new, optimized computer experience is ready.\nChoose your preferred interface style:"
MODE=$(yad --title="Axiom OS" --text="$MSG" --button="Laptop Mode:0" --button="Tablet Mode:2" --width=450)

if [ $? -eq 0 ]; then
    kwriteconfig5 --file plasma-org.kde.plasma.desktop-appletsrc --group Panels --group 1 --key Thickness 40
else
    kwriteconfig5 --file plasma-org.kde.plasma.desktop-appletsrc --group Panels --group 1 --key Thickness 80
fi
busctl --user call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell refreshCurrentShell
MODE_EOT
chmod +x /usr/local/bin/axiom-mode-toggle

# 4. Final Performance (Invisible and Fast)
echo 'ALGO=lz4' > /etc/default/zramswap
echo 'PERCENT=60' >> /etc/default/zramswap

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
