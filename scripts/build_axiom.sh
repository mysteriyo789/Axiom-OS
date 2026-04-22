#!/bin/bash
# Axiom OS Master Build Script
# Version: 1.3.0 (Infrastructure + Identity + Utilities)
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
apt-get install -y --no-install-recommends \
    wget ca-certificates gnupg2 linux-image-generic initramfs-tools casper \
    sddm plasma-desktop-data plasma-workspace plasma-nm \
    network-manager kde-cli-tools ubiquity ubiquity-frontend-gtk \
    yad imagemagick zram-config maliit-keyboard qtwayland5 iio-sensor-proxy \
    papirus-icon-theme dolphin wireguard-tools rofi xclip bubblewrap ffmpeg

# --- AXIOM IDENTITY SYSTEM ("The Silent Feather") ---
LOGO_DIR="/etc/axiom/ui/branding"
ICON_DIR="/usr/share/icons/hicolor/scalable/apps"
mkdir -p "$LOGO_DIR" "$ICON_DIR"

cat <<'SVG_EOT' > "$LOGO_DIR/axiom-logo.svg"
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
SVG_EOT

cat <<'SVG_EOT' > "$ICON_DIR/axiom-apphub.svg"
<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <path d="M50 15 L85 75 L50 90 L15 75 Z" fill="white"/>
  <path d="M50 15 L50 90" stroke="#1A1B26" stroke-width="2"/>
</svg>
SVG_EOT

cp "$LOGO_DIR/axiom-logo.svg" "$ICON_DIR/axiom-launcher.svg"

# --- AXIOM PRO UTILITIES ---
# 1. Infinite Clipboard
wget -q https://github.com/erebe/greenclip/releases/download/v4.2/greenclip -O /usr/local/bin/greenclip
chmod +x /usr/local/bin/greenclip

# 2. Execution in Void
cat <<'VOID_EOT' > /usr/local/bin/axiom-void
#!/bin/bash
bwrap --ro-bind /usr /usr --ro-bind /lib /lib --ro-bind /bin /bin --ro-bind /etc /etc \
      --proc /proc --dev /dev --tmpfs /tmp --tmpfs /home --unshare-all --share-net --die-with-parent "$@"
VOID_EOT
chmod +x /usr/local/bin/axiom-void

# --- DESKTOP CONFIGURATION ---
mkdir -p /etc/skel/.config
cat <<ICON_EOT > /etc/skel/.config/kdeglobals
[Icons]
Theme=Papirus-Dark
[General]
ColorScheme=BreezeDark
ICON_EOT

# UI Toggle Script
cat <<'MODE_EOT' > /usr/local/bin/axiom-mode-toggle
#!/bin/bash
MSG="<b>Interface Selection</b>"
MODE=$(yad --title="Settings" --text="$MSG" --button="Laptop Mode:0" --button="Tablet Mode:2" --width=350)
if [ $? -eq 0 ]; then
    kwriteconfig5 --file plasma-org.kde.plasma.desktop-appletsrc --group Panels --group 1 --key location "bottom"
else
    kwriteconfig5 --file plasma-org.kde.plasma.desktop-appletsrc --group Panels --group 1 --key location "top"
fi
busctl --user call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell refreshCurrentShell
MODE_EOT
chmod +x /usr/local/bin/axiom-mode-toggle

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

echo "--- Build Complete: output/AxiomOS.iso generated ---"
