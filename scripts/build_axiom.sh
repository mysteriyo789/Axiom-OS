#!/bin/bash
set -e

# --- 1. ENVIRONMENT ---
ROOT=$(pwd)/axiom_rootfs
ISO_DIR=$(pwd)/axiom_iso
mkdir -p "$ROOT" "$ISO_DIR/live" output
export DEBIAN_FRONTEND=noninteractive

echo "--- Bootstrapping Axiom OS ---"
sudo debootstrap --arch amd64 jammy "$ROOT" http://archive.ubuntu.com/ubuntu/

# Mount virtual filesystems
sudo mount --bind /dev "$ROOT/dev"
sudo mount --bind /run "$ROOT/run"
sudo mount -t proc proc "$ROOT/proc"
sudo mount -t sysfs sys "$ROOT/sys"

sudo chroot "$ROOT" /bin/bash <<EOF
export DEBIAN_FRONTEND=noninteractive

# Setup Repositories
cat <<EOT > /etc/apt/sources.list
deb http://archive.ubuntu.com/ubuntu/ jammy main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ jammy-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ jammy-security main restricted universe multiverse
EOT

apt-get update

# Install Kernel and Core - Added 'linux-generic' for full headers and image
apt-get install -y wget curl ca-certificates gnupg2
apt-get install -y --no-install-recommends \
    linux-generic initramfs-tools casper \
    sddm plasma-desktop plasma-nm network-manager \
    kde-cli-tools ubiquity ubiquity-frontend-gtk \
    spectacle ark iio-sensor-proxy power-profiles-daemon \
    yad imagemagick plasma-systemmonitor systemsettings \
    zram-config maliit-keyboard qtwayland5

# Install Chrome Engine
wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
apt-get install -y ./google-chrome-stable_current_amd64.deb || apt-get install -f -y
rm google-chrome-stable_current_amd64.deb

# --- FEATURE SCRIPTS ---
mkdir -p /usr/local/bin

# 1. Interface Mode Toggle
cat <<'MODE_EOT' > /usr/local/bin/axiom-mode-toggle
#!/bin/bash
MSG="Welcome to Axiom OS.\n\nChoose the interface style that fits your workflow.\n\n<b>Note:</b> You can switch styles anytime in\n<b>Settings > Hardware > Interface Style</b>."
MODE=\$(yad --title="Axiom Interface Setup" --window-icon="preferences-desktop-display" --text="\$MSG" --text-align=center --width=480 --button="Laptop Style:0" --button="Tablet Style (Android):2")
if [ \$? -eq 0 ]; then
    kwriteconfig5 --file plasma-org.kde.plasma.desktop-appletsrc --group Panels --group 1 --key Thickness 40
    kwriteconfig5 --file plasma-org.kde.plasma.desktop-appletsrc --group Containments --group 1 --key plugin "org.kde.desktopcontainment"
    kwriteconfig5 --file plasma-org.kde.plasma.desktop-appletsrc --group Applets --group 2 --key plugin "org.kde.plasma.taskmanager"
else
    kwriteconfig5 --file plasma-org.kde.plasma.desktop-appletsrc --group Panels --group 1 --key Thickness 80
    kwriteconfig5 --file plasma-org.kde.plasma.desktop-appletsrc --group Applets --group 1 --key plugin "org.kde.plasma.kicker"
    kwriteconfig5 --file plasma-org.kde.plasma.desktop-appletsrc --group Applets --group 2 --key plugin "org.kde.plasma.icontasks"
    kwriteconfig5 --file plasma-org.kde.plasma.desktop-appletsrc --group Containments --group 1 --key plugin "org.kde.plasma.extras.empty"
    kwriteconfig5 --file kwinrc --group EdgeBarrier --key EdgeBarrier 0
    kwriteconfig5 --file kwinrc --group Effect-PresentWindows --key BorderActivate 7
fi
kwriteconfig5 --file kwinrc --group Wayland --key InputMethod "/usr/share/applications/com.github.maliit.keyboard.desktop"
busctl --user call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell refreshCurrentShell
MODE_EOT
chmod +x /usr/local/bin/axiom-mode-toggle

# 2. App Store (Consolidated)
cat <<'STORE_EOT' > /usr/local/bin/app-store
#!/bin/bash
install_app() {
    NAME=\$1; URL=\$2
    ICON_DIR="\$HOME/.local/share/icons/apps"; APP_DIR="\$HOME/.local/share/applications"
    mkdir -p "\$APP_DIR" "\$ICON_DIR"
    DOMAIN=\$(echo "\$URL" | awk -F[/] '{print \$1"//"\$3}')
    wget -qO "\$ICON_DIR/\${NAME}.png" "https://www.google.com/s2/favicons?sz=128&domain=\$DOMAIN"
    echo -e "[Desktop Entry]\nName=\$NAME\nExec=google-chrome-stable --app=\$URL\nIcon=\$ICON_DIR/\${NAME}.png\nType=Application" > "\$APP_DIR/app-\${NAME,,}.desktop"
    notify-send "App Store" "\$NAME installed."
}
export -f install_app
yad --title="App Store" --width=700 --height=500 --list --radiolist --column="Select" --column="App" --column="Type" --column="Action" \
    FALSE "YouTube" "Video" "bash -c 'install_app YouTube https://youtube.com'" \
    FALSE "ChatGPT" "AI" "bash -c 'install_app ChatGPT https://chat.openai.com'" \
    --button="Install:0" --button="Close:1"
STORE_EOT
chmod +x /usr/local/bin/app-store

# --- CONFIG & UI ---
mkdir -p /etc/skel/.config/autostart
cat <<EOT > /etc/skel/.config/autostart/axiom-welcome.desktop
[Desktop Entry]
Type=Application
Exec=bash -c "axiom-mode-toggle && rm ~/.config/autostart/axiom-welcome.desktop"
Name=Axiom Welcome
EOT

cat <<EOT > /usr/share/applications/axiom-mode.desktop
[Desktop Entry]
Name=Interface Style
Exec=axiom-mode-toggle
Icon=preferences-desktop-display
Type=Application
Categories=Settings;X-KDE-settings-hardware;
EOT

mkdir -p /usr/share/wallpapers
wget -qO "/usr/share/wallpapers/axiom_multicolor.jpg" "https://images.unsplash.com/photo-1549880181-56a44cf4a9a1?q=80&w=2560"

apt-get autoremove -y && apt-get clean
EOF

# --- FINAL PACKAGING (FIXED GLOBBING) ---
# Verification check
ls -lh "$ROOT/boot/"

# Using a more robust copy method for the kernel
sudo cp -v "$ROOT"/boot/vmlinuz-*-generic "$ISO_DIR/live/vmlinuz" || (echo "FAILED TO FIND KERNEL" && exit 1)
sudo cp -v "$ROOT"/boot/initrd.img-*-generic "$ISO_DIR/live/initrd" || (echo "FAILED TO FIND INITRD" && exit 1)

sudo umount -l "$ROOT/dev" "$ROOT/run" "$ROOT/proc" "$ROOT/sys" || true
sudo mksquashfs "$ROOT" output/AxiomOS.iso -comp xz
