#!/bin/bash
set -e

ROOT=$(pwd)/axiom_rootfs
ISO_DIR=$(pwd)/axiom_iso
mkdir -p "$ROOT" "$ISO_DIR/live" output
export DEBIAN_FRONTEND=noninteractive

echo "--- Building Axiom OS: Android Hybrid Edition ---"
sudo debootstrap --arch amd64 jammy "$ROOT" http://archive.ubuntu.com/ubuntu/

# Mount virtual filesystems
sudo mount --bind /dev "$ROOT/dev"
sudo mount --bind /run "$ROOT/run"
sudo mount -t proc proc "$ROOT/proc"
sudo mount -t sysfs sys "$ROOT/sys"

sudo chroot "$ROOT" /bin/bash <<EOF
export DEBIAN_FRONTEND=noninteractive

# 1. CORE & REPOS
cat <<EOT > /etc/apt/sources.list
deb http://archive.ubuntu.com/ubuntu/ jammy main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ jammy-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ jammy-security main restricted universe multiverse
EOT

apt-get update
# Added Maliit for the On-Screen Keyboard and iio-sensor-proxy for rotation
apt-get install -y wget curl ca-certificates gnupg2
apt-get install -y --no-install-recommends \
    linux-generic initramfs-tools casper \
    sddm plasma-desktop plasma-nm network-manager \
    ubiquity ubiquity-frontend-gtk spectacle ark \
    iio-sensor-proxy power-profiles-daemon yad imagemagick \
    plasma-systemmonitor systemsettings zram-config \
    maliit-keyboard qtwayland5

# 2. CHROME & PERFORMANCE
wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
apt-get install -y ./google-chrome-stable_current_amd64.deb || apt-get install -f -y
rm google-chrome-stable_current_amd64.deb

# Enable ZRAM for "Always Fast" performance
echo 'ALGO=lz4' >> /etc/default/zramswap
echo 'PERCENT=60' >> /etc/default/zramswap

# 3. THE HYBRID ENGINE (LAPTOP vs ANDROID-STYLE)
cat <<'MODE_EOT' > /usr/local/bin/axiom-mode-toggle
#!/bin/bash
MSG="Welcome to Axiom OS.\n\nChoose the interface style that fits your workflow.\n\n<b>Note:</b> You can switch styles anytime in\n<b>Settings > Hardware > Interface Style</b>.\n\n<i>On-screen keyboard is always available via touch.</i>"

MODE=\$(yad --title="Axiom Interface Setup" --window-icon="preferences-desktop-display" \
    --text="\$MSG" --text-align=center --width=480 \
    --button="Laptop Style:0" --button="Tablet Style (Android):2")

if [ \$? -eq 0 ]; then
    # --- LAPTOP MODE ---
    kwriteconfig5 --file plasma-org.kde.plasma.desktop-appletsrc --group Panels --group 1 --key Thickness 40
    # Standard Menu and Desktop
    kwriteconfig5 --file plasma-org.kde.plasma.desktop-appletsrc --group Applets --group 1 --key plugin "org.kde.plasma.kickoff"
    kwriteconfig5 --file plasma-org.kde.plasma.desktop-appletsrc --group Containments --group 1 --key plugin "org.kde.desktopcontainment"
    # Traditional Taskbar (Icons + Labels)
    kwriteconfig5 --file plasma-org.kde.plasma.desktop-appletsrc --group Applets --group 2 --key plugin "org.kde.plasma.taskmanager"
else
    # --- TABLET (ANDROID) MODE ---
    kwriteconfig5 --file plasma-org.kde.plasma.desktop-appletsrc --group Panels --group 1 --key Thickness 80
    # SWAP 1: Full-Screen Launcher (Dashboard)
    kwriteconfig5 --file plasma-org.kde.plasma.desktop-appletsrc --group Applets --group 1 --key plugin "org.kde.plasma.kicker"
    # SWAP 2: Icon-Only Dock (Android Style)
    kwriteconfig5 --file plasma-org.kde.plasma.desktop-appletsrc --group Applets --group 2 --key plugin "org.kde.plasma.icontasks"
    # SWAP 3: Clean Desktop (No Icons)
    kwriteconfig5 --file plasma-org.kde.plasma.desktop-appletsrc --group Containments --group 1 --key plugin "org.kde.plasma.extras.empty"
    # SWAP 4: Android "Recents" Gesture (Bottom Edge)
    kwriteconfig5 --file kwinrc --group EdgeBarrier --key EdgeBarrier 0
    kwriteconfig5 --file kwinrc --group Effect-PresentWindows --key BorderActivate 7
fi

# Universal: Enable On-Screen Keyboard Support
kwriteconfig5 --file kwinrc --group Wayland --key InputMethod "/usr/share/applications/com.github.maliit.keyboard.desktop"

busctl --user call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell refreshCurrentShell
MODE_EOT
chmod +x /usr/local/bin/axiom-mode-toggle

# 4. FIRST-BOOT & SETTINGS
mkdir -p /etc/skel/.config/autostart
cat <<EOT > /etc/skel/.config/autostart/axiom-welcome.desktop
[Desktop Entry]
Type=Application
Exec=bash -c "axiom-mode-toggle && rm ~/.config/autostart/axiom-welcome.desktop"
Name=Axiom Welcome
EOT

cat <<EOT > /usr/share/applications/axiom-mode.desktop
[Desktop Entry]
Name=Interface Style (Laptop/Tablet)
Exec=axiom-mode-toggle
Icon=preferences-desktop-display
Type=Application
Categories=Settings;X-KDE-settings-hardware;
EOT

# 5. APP STORE LOGIC (Abbreviated for brevity)
# [Insert App Store code from previous turn here]

# 6. UI THEMING
W_PATH="/usr/share/wallpapers/axiom_multicolor.jpg"
wget -qO "\$W_PATH" "https://images.unsplash.com/photo-1549880181-56a44cf4a9a1?q=80&w=2560"
mkdir -p /etc/skel/.config
kwriteconfig5 --file /etc/skel/.config/kdeglobals --group General --key accentColor --type string "auto"

apt-get autoremove -y && apt-get clean
EOF

# 7. PACKAGE
sudo umount -l "$ROOT/dev" "$ROOT/run" "$ROOT/proc" "$ROOT/sys" || true
sudo cp "$ROOT"/boot/vmlinuz-*-generic "$ISO_DIR/live/vmlinuz"
sudo cp "$ROOT"/boot/initrd.img-*-generic "$ISO_DIR/live/initrd"
sudo mksquashfs "$ROOT" output/AxiomOS.iso -comp xz
