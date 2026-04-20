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

# Repositories
cat <<EOT > /etc/apt/sources.list
deb http://archive.ubuntu.com/ubuntu/ jammy main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ jammy-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ jammy-security main restricted universe multiverse
EOT

apt-get update
apt-get install -y --no-install-recommends wget ca-certificates gnupg2 linux-image-generic initramfs-tools casper

# Install UI and the Vibrant Icon Theme (Papirus is best for colorful category icons)
apt-get install -y --no-install-recommends \
    sddm plasma-desktop-data plasma-workspace plasma-nm \
    network-manager kde-cli-tools ubiquity ubiquity-frontend-gtk \
    yad imagemagick zram-config maliit-keyboard qtwayland5 iio-sensor-proxy \
    papirus-icon-theme dolphin

# Install the Axiom Runtime Engine (Chrome)
wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
apt-get install -y ./google-chrome-stable_current_amd64.deb || apt-get install -f -y
rm google-chrome-stable_current_amd64.deb

# --- AXIOM CUSTOMIZATIONS ---
mkdir -p /usr/local/bin /usr/share/applications /etc/skel/.config

# 1. Branding: Files & Settings
# This creates the "Files" entry that opens the manager with the right look
cat <<EOT > /usr/share/applications/axiom-files.desktop
[Desktop Entry]
Name=Files
Exec=dolphin %u
Icon=system-file-manager
Type=Application
Categories=System;FileTools;
GenericName=File Browser
EOT

cat <<EOT > /usr/share/applications/axiom-settings.desktop
[Desktop Entry]
Name=Settings
Exec=systemsettings
Icon=preferences-system
Type=Application
Categories=Settings;
EOT

# 2. Force Vibrant Theme & Sidebar Layout
# We pre-configure the user's config so it starts with colorful icons and a clean sidebar
cat <<ICON_EOT > /etc/skel/.config/kdeglobals
[Icons]
Theme=Papirus-Dark

[General]
ColorScheme=BreezeDark
ICON_EOT

# Configure Dolphin (Files) to show the Places panel clearly
cat <<DOLPHIN_EOT > /etc/skel/.config/dolphinrc
[General]
ShowFullPath=false
ViewMode=1

[PlacesPanel]
IconSize=32
DOLPHIN_EOT

# 3. Manual UI Toggle (Top Bar vs Bottom Bar)
cat <<'MODE_EOT' > /usr/local/bin/axiom-mode-toggle
#!/bin/bash
MSG="<b>Interface Selection</b>"
MODE=$(yad --title="Settings" --text="$MSG" --button="Laptop Mode:0" --button="Tablet Mode:2" --width=350)

if [ $? -eq 0 ]; then
    kwriteconfig5 --file plasma-org.kde.plasma.desktop-appletsrc --group Panels --group 1 --key location "bottom"
    kwriteconfig5 --file plasma-org.kde.plasma.desktop-appletsrc --group Panels --group 1 --key Thickness 40
else
    kwriteconfig5 --file plasma-org.kde.plasma.desktop-appletsrc --group Panels --group 1 --key location "top"
    kwriteconfig5 --file plasma-org.kde.plasma.desktop-appletsrc --group Panels --group 1 --key Thickness 30
fi
busctl --user call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell refreshCurrentShell
MODE_EOT
chmod +x /usr/local/bin/axiom-mode-toggle

# Disable auto-tablet switching
echo -e "[TabletMode]\nTabletMode=never" > /etc/skel/.config/kwinrc

apt-get clean
rm -rf /var/lib/apt/lists/*
EOF

# --- 4. PACKAGING ---
VMLINUZ=$(find "$ROOT/boot" -name "vmlinuz-*-generic" | head -n 1)
INITRD=$(find "$ROOT/boot" -name "initrd.img-*-generic" | head -n 1)
sudo cp -v "$VMLINUZ" "$ISO_DIR/live/vmlinuz"
sudo cp -v "$INITRD" "$ISO_DIR/live/initrd"
sudo umount -l "$ROOT/sys" "$ROOT/proc" "$ROOT/run" "$ROOT/dev"
sudo mksquashfs "$ROOT" output/AxiomOS.iso -comp gzip -no-progress
