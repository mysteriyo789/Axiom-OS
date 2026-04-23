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
# Using a unique, quoted delimiter to prevent variable expansion and nesting issues
sudo chroot "$ROOT" /bin/bash <<'MAIN_CHROOT_EOF'
export DEBIAN_FRONTEND=noninteractive

# Repositories
cat <<REPOS_EOT > /etc/apt/sources.list
deb http://archive.ubuntu.com/ubuntu/ jammy main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ jammy-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ jammy-security main restricted universe multiverse
REPOS_EOT

apt-get update
apt-get install -y --no-install-recommends \
    wget ca-certificates gnupg2 linux-image-generic initramfs-tools casper \
    wireguard-tools rofi xclip bubblewrap ffmpeg

apt-get install -y --no-install-recommends \
    sddm plasma-desktop-data plasma-workspace plasma-nm \
    network-manager kde-cli-tools ubiquity ubiquity-frontend-gtk \
    yad imagemagick zram-config maliit-keyboard qtwayland5 iio-sensor-proxy \
    papirus-icon-theme dolphin

# Install Chrome
wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
apt-get install -y ./google-chrome-stable_current_amd64.deb || apt-get install -f -y
rm google-chrome-stable_current_amd64.deb

# --- AXIOM CUSTOMIZATIONS ---
mkdir -p /usr/local/bin /usr/share/applications /etc/skel/.config
mkdir -p /etc/axiom/ui/branding /usr/share/icons/hicolor/scalable/apps

# 1. Identity System
cat <<'LOGO_SVG' > /etc/axiom/ui/branding/axiom-logo.svg
<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <mask id="AxiomFeatherMask">
      <circle cx="50" cy="50" r="48" fill="white"/>
      <path d="M52 82 C 55 70 52 58 48 48 C 45 40 46 30 50 20 L 48 18 C 42 28 41 40 44 50 C 47 60 48 72 45 84 Z" fill="black"/>
      <path d="M48 18 C 30 25 32 45 35 60 C 37 75 32 82 45 84 Z" fill="black"/>
    </mask>
  </defs>
  <circle cx="50" cy="50" r="48" fill="white" mask="url(#AxiomFeatherMask)"/>
</svg>
LOGO_SVG

cat <<'HUB_SVG' > /usr/share/icons/hicolor/scalable/apps/axiom-apphub.svg
<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <path d="M50 15 L85 75 L50 90 L15 75 Z" fill="white"/>
  <path d="M50 15 L50 90" stroke="#1A1B26" stroke-width="2"/>
</svg>
HUB_SVG

cp /etc/axiom/ui/branding/axiom-logo.svg /usr/share/icons/hicolor/scalable/apps/axiom-launcher.svg

# 2. Pro Utilities Core
if [ ! -f /etc/wireguard/axiom0.key ]; then
    wg genkey | tee /etc/wireguard/axiom0.key | wg pubkey | tee /etc/wireguard/axiom0.pub > /dev/null
fi

wget -q https://github.com/erebe/greenclip/releases/download/v4.2/greenclip -O /usr/local/bin/greenclip
chmod +x /usr/local/bin/greenclip

cat <<'VOID_SCRIPT' > /usr/local/bin/axiom-void
#!/bin/bash
bwrap --ro-bind /usr /usr --ro-bind /lib /lib --ro-bind /bin /bin --ro-bind /etc /etc \
      --proc /proc --dev /dev --tmpfs /tmp --tmpfs /home --unshare-all --share-net --die-with-parent "$@"
VOID_SCRIPT
chmod +x /usr/local/bin/axiom-void

# 3. Desktop Entries
cat <<'FILES_EOT' > /usr/share/applications/axiom-files.desktop
[Desktop Entry]
Name=Files
Exec=dolphin %u
Icon=system-file-manager
Type=Application
Categories=System;FileTools;
GenericName=File Browser
FILES_EOT

cat <<'SETTINGS_EOT' > /usr/share/applications/axiom-settings.desktop
[Desktop Entry]
Name=Settings
Exec=systemsettings
Icon=preferences-system
Type=Application
Categories=Settings;
SETTINGS_EOT

# 4. Media Transcoder
mkdir -p /etc/skel/.local/share/nemo/actions
cat <<'NEMO_EOT' > /etc/skel/.local/share/nemo/actions/transcode_mp4.nemo_action
[Nemo Action]
Active=true
Name=Transcode to MP4 (Axiom Core)
Exec=ffmpeg -i %f -c:v libx264 -crf 23 -c:a aac -b:a 192k %f.mp4
Selection=s
Extensions=mkv;avi;mov;webm;
NEMO_EOT

# 5. Theme & UI
cat <<'KDE_EOT' > /etc/skel/.config/kdeglobals
[Icons]
Theme=Papirus-Dark
[General]
ColorScheme=BreezeDark
KDE_EOT

cat <<'DOLPHIN_EOT' > /etc/skel/.config/dolphinrc
[General]
ShowFullPath=false
ViewMode=1
[PlacesPanel]
IconSize=32
DOLPHIN_EOT

# 6. Manual UI Toggle
cat <<'MODE_SCRIPT' > /usr/local/bin/axiom-mode-toggle
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
MODE_SCRIPT
chmod +x /usr/local/bin/axiom-mode-toggle

echo -e "[TabletMode]\nTabletMode=never" > /etc/skel/.config/kwinrc

apt-get clean
rm -rf /var/lib/apt/lists/*
MAIN_CHROOT_EOF

# --- 4. PACKAGING ---
VMLINUZ=$(find "$ROOT/boot" -name "vmlinuz-*-generic" | head -n 1)
INITRD=$(find "$ROOT/boot" -name "initrd.img-*-generic" | head -n 1)
sudo cp -v "$VMLINUZ" "$ISO_DIR/live/vmlinuz"
sudo cp -v "$INITRD" "$ISO_DIR/live/initrd"
sudo umount -l "$ROOT/sys" "$ROOT/proc" "$ROOT/run" "$ROOT/dev"
sudo mksquashfs "$ROOT" output/AxiomOS.iso -comp gzip -no-progress
