#!/bin/bash
set -e

# --- 1. SETUP ---
ROOT=$(pwd)/axiom_rootfs
ISO_DIR=$(pwd)/axiom_iso
mkdir -p "$ROOT" "$ISO_DIR/live" output
export DEBIAN_FRONTEND=noninteractive

# --- 2. BOOTSTRAP ---
echo "--- Bootstrapping Core ---"
sudo debootstrap --arch amd64 jammy "$ROOT" http://azure.archive.ubuntu.com/ubuntu/

# --- 3. CHROOT CUSTOMIZATION ---
sudo mount --bind /dev "$ROOT/dev"
sudo mount --bind /run "$ROOT/run"
sudo mount -t proc proc "$ROOT/proc"
sudo mount -t sysfs sys "$ROOT/sys"

sudo chroot "$ROOT" /bin/bash <<EOF
export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C

# Mirrors & Updates
printf "deb http://azure.archive.ubuntu.com/ubuntu/ jammy main restricted universe multiverse\n" > /etc/apt/sources.list
printf "deb http://azure.archive.ubuntu.com/ubuntu/ jammy-updates main restricted universe multiverse\n" >> /etc/apt/sources.list
apt-get update

# AXIOM CORE STACK
# Includes: Desktop, Kernel, Adaptive Hardware Drivers, Recovery, and Input Methods
apt-get install -y --yes -o Dpkg::Options::="--force-confold" --no-install-recommends \
    linux-generic initramfs-tools casper wget ca-certificates \
    sddm plasma-desktop plasma-nm network-manager \
    ubiquity ubiquity-frontend-gtk spectacle ark \
    iio-sensor-proxy power-profiles-daemon libinput-tools \
    maliit-framework maliit-keyboard-qt5 \
    timeshift okular discover plasma-systemmonitor \
    filelight ufw systemsettings

# Install Chrome (The PWA Engine)
wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
apt-get install -y ./google-chrome-stable_current_amd64.deb
rm google-chrome-stable_current_amd64.deb

# --- AXIOM NATIVE SETTINGS & TOOLS ---

# Device Mode Toggle (UI Scaling)
cat <<'EOT' > /usr/local/bin/axiom-mode-toggle
#!/bin/bash
MODE=\$1
CONF="\$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
if [ "\$MODE" == "tablet" ] || [ "\$(grep "Thickness=44" "\$CONF")" ]; then
    sed -i 's/Thickness=44/Thickness=64/g' "\$CONF"
    notify-send "Axiom OS" "Tablet Mode: UI Optimized for Touch"
else
    sed -i 's/Thickness=64/Thickness=44/g' "\$CONF"
    notify-send "Axiom OS" "Laptop Mode: UI Optimized for Mouse"
fi
busctl --user call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell refreshCurrentShell
EOT

# Dark Mode & Shelf Toggles
cat <<'EOT' > /usr/local/bin/axiom-dark-toggle
#!/bin/bash
look-and-feeltool --list | grep -q "dark" && look-and-feeltool -a org.kde.breeze.desktop || look-and-feeltool -a org.kde.breezedark.desktop
EOT

cat <<'EOT' > /usr/local/bin/axiom-shelf-toggle
#!/bin/bash
CONF="\$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
grep -q "Floating=1" "\$CONF" && sed -i 's/Floating=1/Floating=0/g' "\$CONF" || (sed -i 's/Floating=0/Floating=1/g' "\$CONF" || sed -i '/\[Panels\]\[1\]/a Floating=1' "\$CONF")
busctl --user call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell refreshCurrentShell
EOT

chmod +x /usr/local/bin/axiom-mode-toggle /usr/local/bin/axiom-dark-toggle /usr/local/bin/axiom-shelf-toggle

# Register Settings Entries (The Professional Suite)
mkdir -p /usr/share/applications
cat <<EOT > /usr/share/applications/axiom-mode.desktop
[Desktop Entry]
Name=Device Mode
Exec=axiom-mode-toggle
Icon=input-tablet
Type=Application
Categories=Settings;
X-KDE-Settings-ParentCategory=appearance
EOT

cat <<EOT > /usr/share/applications/axiom-dark.desktop
[Desktop Entry]
Name=Dark Mode
Exec=axiom-dark-toggle
Icon=preferences-desktop-color
Type=Application
Categories=Settings;
X-KDE-Settings-ParentCategory=appearance
EOT

cat <<EOT > /usr/share/applications/axiom-night.desktop
[Desktop Entry]
Name=Night Light
Exec=systemsettings5 kcm_nightcolor
Icon=preferences-desktop-display-nightcolor
Type=Application
Categories=Settings;
X-KDE-Settings-ParentCategory=displayandmonitor
EOT

# --- AXIOM STORE (PWA INTEGRATION) ---
declare -A PWAS=( ["Calendar"]="https://calendar.google.com" ["Keep"]="https://keep.google.com" ["Meet"]="https://meet.google.com" ["Photos"]="https://photos.google.com" ["Maps"]="https://maps.google.com" )
for NAME in "\${!PWAS[@]}"; do
    URL=\${PWAS[\$NAME]}
    echo -e "[Desktop Entry]\nName=\$NAME\nExec=google-chrome-stable --app=\$URL\nIcon=google-chrome\nType=Application\nCategories=AxiomStore;" > /usr/share/applications/axiom-\${NAME,,}.desktop
done

# --- SYSTEM DEFAULTS (SKEL) ---
mkdir -p /etc/skel/.config
cat <<EOT > /etc/skel/.config/kwinrc
[Wayland]
InputMethod=/usr/share/applications/com.github.maliit.keyboard.desktop
EOT

cat <<EOT > /etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc
[Panels][1]
Alignment=Center
Location=Bottom
Thickness=44
LengthMode=Fill
Floating=0
[Applets][2]
plugin=org.kde.plasma.taskmanager
Configuration=showOnlyCurrentDesktop:true;launchers=google-chrome.desktop,gmail.desktop,docs.desktop,drive.desktop,files.desktop,settings.desktop,health.desktop,org.kde.discover.desktop
[Applets][3]
plugin=org.kde.plasma.battery
Appearance=showPercentage:true
EOT

# Cleaning Bloat
apt-get purge -y thunderbird libreoffice* gnome-software kwrite kate
apt-get autoremove -y
apt-get clean
EOF

# --- 4. PACKAGING ---
sudo umount -l "$ROOT/dev" "$ROOT/run" "$ROOT/proc" "$ROOT/sys" || true
sudo cp "$ROOT"/boot/vmlinuz-*-generic "$ISO_DIR/live/vmlinuz"
sudo cp "$ROOT"/boot/initrd.img-*-generic "$ISO_DIR/live/initrd"
sudo mksquashfs "$ROOT" output/AxiomOS.iso -comp xz
