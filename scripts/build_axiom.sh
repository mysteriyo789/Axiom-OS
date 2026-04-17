#!/bin/bash
set -e

# --- 1. PREPARATION ---
ROOT=$(pwd)/axiom_rootfs
ISO_DIR=$(pwd)/axiom_iso
mkdir -p "$ROOT" "$ISO_DIR/live" output
export DEBIAN_FRONTEND=noninteractive

echo "--- Bootstrapping Axiom OS (Jammy) ---"
sudo debootstrap --arch amd64 jammy "$ROOT" http://azure.archive.ubuntu.com/ubuntu/

# --- 2. MOUNT VIRTUAL FILESYSTEMS ---
sudo mount --bind /dev "$ROOT/dev"
sudo mount --bind /run "$ROOT/run"
sudo mount -t proc proc "$ROOT/proc"
sudo mount -t sysfs sys "$ROOT/sys"

# --- 3. SYSTEM CUSTOMIZATION (CHROOT) ---
sudo chroot "$ROOT" /bin/bash <<EOF
export DEBIAN_FRONTEND=noninteractive

# Repositories
printf "deb http://azure.archive.ubuntu.com/ubuntu/ jammy main restricted universe multiverse\n" > /etc/apt/sources.list
printf "deb http://azure.archive.ubuntu.com/ubuntu/ jammy-updates main restricted universe multiverse\n" >> /etc/apt/sources.list
apt-get update

# Install Core UI, Performance, and GUI Tools
apt-get install -y --no-install-recommends \
    linux-generic initramfs-tools casper wget ca-certificates \
    sddm plasma-desktop plasma-nm network-manager \
    ubiquity ubiquity-frontend-gtk spectacle ark \
    iio-sensor-proxy power-profiles-daemon yad ImageMagick \
    plasma-systemmonitor systemsettings zram-config

# Install Google Chrome (The PWA Runtime Engine)
wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
apt-get install -y ./google-chrome-stable_current_amd64.deb || apt-get install -f -y
rm google-chrome-stable_current_amd64.deb

# --- FEATURE: ALWAYS FAST ENGINE (ZRAM) ---
echo 'ALGO=lz4' >> /etc/default/zramswap
echo 'PERCENT=60' >> /etc/default/zramswap

# --- FEATURE: UNIVERSAL AXIOM STORE (SEARCHABLE & GLOBAL) ---
cat <<'EOT' > /usr/local/bin/axiom-store
#!/bin/bash
install_app() {
    NAME=$1; URL=$2
    ICON_DIR="$HOME/.local/share/icons/axiom"; APP_DIR="$HOME/.local/share/applications"
    mkdir -p "$APP_DIR" "$ICON_DIR"
    
    # Universal High-Res Icon Fetcher (128px)
    DOMAIN=$(echo "$URL" | awk -F[/] '{print $1"//"$3}')
    wget -qO "$ICON_DIR/${NAME}.png" "https://www.google.com/s2/favicons?sz=128&domain=$DOMAIN"
    
    FILE="$APP_DIR/axiom-${NAME,,}.desktop"
    echo -e "[Desktop Entry]\nName=$NAME\nExec=google-chrome-stable --app=$URL\nIcon=$ICON_DIR/${NAME}.png\nType=Application\nTerminal=false" > "$FILE"
    chmod +x "$FILE"
    
    # Inject into Center Shelf (Task Manager)
    CURRENT=$(kreadconfig5 --file plasma-org.kde.plasma.desktop-appletsrc --group Panels --group 1 --group Applets --group 2 --key Configuration | grep "launchers=")
    CLEAN_LIST=$(echo "$CURRENT" | sed 's/launchers=//')
    kwriteconfig5 --file plasma-org.kde.plasma.desktop-appletsrc --group Panels --group 1 --group Applets --group 2 --key Configuration --type string "launchers=${CLEAN_LIST},${FILE}"
    
    busctl --user call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell refreshCurrentShell
    notify-send "Axiom Store" "$NAME added to your Shelf."
}
export -f install_app

# The Main Store Interface
ACTION=$(yad --title="Axiom Store" --width=750 --height=550 --list --radiolist --search-column=2 \
    --column="Select" --column="App Name" --column="Category" --column="Action" \
    FALSE "WhatsApp" "Social" "bash -c 'install_app WhatsApp https://web.whatsapp.com'" \
    FALSE "ChatGPT" "AI" "bash -c 'install_app ChatGPT https://chat.openai.com'" \
    FALSE "Spotify" "Music" "bash -c 'install_app Spotify https://open.spotify.com'" \
    FALSE "YouTube" "Video" "bash -c 'install_app YouTube https://youtube.com'" \
    FALSE "Gmail" "Work" "bash -c 'install_app Gmail https://mail.google.com'" \
    FALSE "Canva" "Design" "bash -c 'install_app Canva https://canva.com'" \
    --button="Install Featured:0" --button="Global Search/URL:2" --button="Close:1")

RET=$?
if [ $RET -eq 2 ]; then
    # Global PWA Engine: If it's on the web, it's in the Store.
    USER_INPUT=$(yad --title="Global Axiom Search" --form --field="Enter App Name or URL (e.g. Reddit):")
    ENTRY=$(echo "$USER_INPUT" | cut -d'|' -f1)
    if [[ $ENTRY != http* ]]; then
        TARGET="https://$ENTRY.com"
        FINAL_NAME=$(echo "$ENTRY" | sed 's/./\u&/')
    else
        TARGET=$ENTRY
        FINAL_NAME=$(echo "$TARGET" | awk -F[/.] '{print $(NF-1)}' | sed 's/./\u&/')
    fi
    install_app "$FINAL_NAME" "$TARGET"
fi
EOT
chmod +x /usr/local/bin/axiom-store

# Create System-wide Launcher for Store
cat <<EOT > /usr/share/applications/axiom-store.desktop
[Desktop Entry]
Name=Axiom Store
Exec=axiom-store
Icon=software-store
Type=Application
EOT

# --- FEATURE: MULTICOLOR LANDSCAPE UI ---
W_PATH="/usr/share/wallpapers/axiom_multicolor.jpg"
wget -qO "$W_PATH" "https://images.unsplash.com/photo-1549880181-56a44cf4a9a1?q=80&w=2560"

mkdir -p /etc/skel/.config
# HUD Shortcut (Alt+Space)
cat <<EOT >> /etc/skel/.config/kglobalshortcutsrc
[org.kde.krunner.desktop]
_launch=Alt+Space,none,Run Command
EOT

# Set Automatic Accent Coloring (extracts color from wallpaper)
kwriteconfig5 --file /etc/skel/.config/kdeglobals --group General --key accentColor --type string "auto"

# Configure the Centered "Shelf" and Clean Desktop
cat <<EOT > /etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc
[Panels][1]
Alignment=Center
Location=Bottom
Thickness=50
Floating=true
[Applets][2]
plugin=org.kde.plasma.taskmanager
Configuration=showOnlyCurrentDesktop:true;launchers=google-chrome.desktop,axiom-store.desktop,settings.desktop
[Containments][1]
plugin=org.kde.desktopcontainment
Wallpaper=org.kde.image
WallpaperConfiguration=axiom_multicolor.jpg
EOT

# --- CLEANUP ---
apt-get autoremove -y && apt-get clean
rm -rf /var/lib/apt/lists/*
EOF

# --- 4. ISO COMPILATION ---
echo "--- Compiling Axiom OS ISO ---"
sudo umount -l "$ROOT/dev" "$ROOT/run" "$ROOT/proc" "$ROOT/sys" || true
sudo cp "$ROOT"/boot/vmlinuz-*-generic "$ISO_DIR/live/vmlinuz"
sudo cp "$ROOT"/boot/initrd.img-*-generic "$ISO_DIR/live/initrd"
sudo mksquashfs "$ROOT" output/AxiomOS.iso -comp xz
