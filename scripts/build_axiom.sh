#!/bin/bash
set -e

# --- 1. SETUP ---
ROOT=$(pwd)/axiom_rootfs
ISO_DIR=$(pwd)/axiom_iso
mkdir -p "$ROOT" "$ISO_DIR/live" output
export DEBIAN_FRONTEND=noninteractive

echo "--- Phase 1: Bootstrapping ---"
sudo debootstrap --arch amd64 jammy "$ROOT" http://archive.ubuntu.com/ubuntu/

# Mount necessary filesystems
for dir in dev run proc sys; do
    if [ "$dir" == "proc" ] || [ "$dir" == "sys" ]; then
        sudo mount -t "$dir" "$dir" "$ROOT/$dir"
    else
        sudo mount --bind "/$dir" "$ROOT/$dir"
    fi
done

# --- Phase 2: Chroot Logic ---
# Using a HEREDOC with quoted 'EOF' to prevent local shell expansion
sudo chroot "$ROOT" /bin/bash <<'EOF'
export DEBIAN_FRONTEND=noninteractive
apt-get update

# Install Kernel first (Critical)
apt-get install -y --no-install-recommends \
    linux-image-generic initramfs-tools casper wget curl ca-certificates gnupg2

# Install Desktop and Hybrid Tools
apt-get install -y --no-install-recommends \
    sddm plasma-desktop plasma-nm network-manager kde-cli-tools \
    ubiquity ubiquity-frontend-gtk yad imagemagick \
    zram-config maliit-keyboard qtwayland5 iio-sensor-proxy

# Install Chrome
wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
apt-get install -y ./google-chrome-stable_current_amd64.deb || apt-get install -f -y
rm google-chrome-stable_current_amd64.deb

# Create the Axiom Toggle Script
cat <<'MODE_SCRIPT' > /usr/local/bin/axiom-mode-toggle
#!/bin/bash
MSG="Welcome to Axiom OS.\n\nChoose the interface style that fits your workflow."
MODE=$(yad --title="Axiom Setup" --text="$MSG" --width=450 --button="Laptop:0" --button="Tablet:2")

if [ $? -eq 0 ]; then
    # Laptop Mode
    kwriteconfig5 --file plasma-org.kde.plasma.desktop-appletsrc --group Panels --group 1 --key Thickness 40
    kwriteconfig5 --file plasma-org.kde.plasma.desktop-appletsrc --group Applets --group 2 --key plugin "org.kde.plasma.taskmanager"
else
    # Tablet Mode (Android style)
    kwriteconfig5 --file plasma-org.kde.plasma.desktop-appletsrc --group Panels --group 1 --key Thickness 80
    kwriteconfig5 --file plasma-org.kde.plasma.desktop-appletsrc --group Applets --group 1 --key plugin "org.kde.plasma.kicker"
    kwriteconfig5 --file plasma-org.kde.plasma.desktop-appletsrc --group Applets --group 2 --key plugin "org.kde.plasma.icontasks"
    kwriteconfig5 --file kwinrc --group Effect-PresentWindows --key BorderActivate 7
fi
# Always enable touch keyboard
kwriteconfig5 --file kwinrc --group Wayland --key InputMethod "/usr/share/applications/com.github.maliit.keyboard.desktop"
busctl --user call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell refreshCurrentShell
MODE_SCRIPT
chmod +x /usr/local/bin/axiom-mode-toggle

# Setup Autostart entry
mkdir -p /etc/skel/.config/autostart
cat <<AS_EOT > /etc/skel/.config/autostart/axiom-welcome.desktop
[Desktop Entry]
Type=Application
Exec=bash -c "axiom-mode-toggle && rm ~/.config/autostart/axiom-welcome.desktop"
Name=Axiom Welcome
AS_EOT

apt-get clean
EOF

# --- Phase 3: Kernel Recovery ---
echo "--- Phase 3: Extracting Boot Files ---"

# We use find to avoid syntax errors with globbing (*)
VMLINUZ=$(find "$ROOT/boot" -name "vmlinuz-*-generic" | head -n 1)
INITRD=$(find "$ROOT/boot" -name "initrd.img-*-generic" | head -n 1)

if [ -z "$VMLINUZ" ]; then
    echo "ERROR: Kernel image not found!"
    exit 1
fi

sudo cp -v "$VMLINUZ" "$ISO_DIR/live/vmlinuz"
sudo cp -v "$INITRD" "$ISO_DIR/live/initrd"

# Cleanup
for dir in dev run proc sys; do sudo umount -l "$ROOT/$dir" || true; done

echo "--- Phase 4: Final ISO Build ---"
sudo mksquashfs "$ROOT" output/AxiomOS.iso -comp xz
