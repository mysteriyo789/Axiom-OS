#!/bin/bash
set -e

# --- 1. RUNNER OPTIMIZATION ---
# This clears ~20GB of space to prevent "No space left on device" errors
echo "--- Optimizing Disk Space for GitHub Runner ---"
sudo rm -rf /usr/share/dotnet /usr/local/lib/android /opt/ghc /usr/local/share/powershell || true

ROOT=$(pwd)/axiom_rootfs
ISO_DIR=$(pwd)/axiom_iso
mkdir -p "$ROOT" "$ISO_DIR/live" output
export DEBIAN_FRONTEND=noninteractive

# --- 2. BOOTSTRAP ---
echo "--- Bootstrapping Base System ---"
sudo debootstrap --arch amd64 jammy "$ROOT" http://azure.archive.ubuntu.com/ubuntu/

# --- 3. CHROOT CUSTOMIZATION ---
sudo mount --bind /dev "$ROOT/dev"
sudo mount --bind /run "$ROOT/run"
sudo mount -t proc proc "$ROOT/proc"
sudo mount -t sysfs sys "$ROOT/sys"

sudo chroot "$ROOT" /bin/bash <<EOF
export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C

# Setup Repositories
printf "deb http://azure.archive.ubuntu.com/ubuntu/ jammy main restricted universe multiverse\n" > /etc/apt/sources.list
printf "deb http://azure.archive.ubuntu.com/ubuntu/ jammy-updates main restricted universe multiverse\n" >> /etc/apt/sources.list
apt-get update

# Pre-configure SDDM to prevent the installer from hanging on a prompt
echo "sddm shared/default-x-display-manager select sddm" | debconf-set-selections

# Step-wise installation (Better for low-memory environments)
echo "--- Installing Core Components ---"
apt-get install -y --no-install-recommends linux-generic initramfs-tools casper wget ca-certificates
apt-get install -y --no-install-recommends sddm plasma-desktop plasma-nm network-manager
apt-get install -y --no-install-recommends ubiquity ubiquity-frontend-gtk spectacle ark 
apt-get install -y --no-install-recommends iio-sensor-proxy power-profiles-daemon libinput-tools
apt-get install -y --no-install-recommends maliit-framework maliit-keyboard-qt5
apt-get install -y --no-install-recommends timeshift okular discover plasma-systemmonitor filelight ufw systemsettings

# Install Google Chrome (PWA Engine)
wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
apt-get install -y ./google-chrome-stable_current_amd64.deb || apt-get install -f -y
rm google-chrome-stable_current_amd64.deb

# --- AXIOM SYSTEM SCRIPTS ---

# 1. Device Mode Toggle (Adaptive UI logic)
cat <<'EOT' > /usr/local/bin/axiom-mode-toggle
#!/bin/bash
MODE=\$1
CONF="\$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
# If no mode provided, toggle based on current thickness
if [ "\$MODE" == "" ]; then
    if grep -q "Thickness=44" "\$CONF"; then MODE="tablet"; else MODE="laptop"; fi
fi

if [ "\$MODE" == "tablet" ]; then
    sed -i 's/Thickness=44/Thickness=64/g' "\$CONF"
    notify-send "Axiom OS" "Adaptive UI: Tablet Mode"
else
    sed -i 's/Thickness=64/Thickness=44/g' "\$CONF"
    notify-send "Axiom OS" "Adaptive UI: Laptop Mode"
fi
busctl --user call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell refreshCurrentShell
EOT

# 2. Universal Hardware Monitor (Auto-Detect Hinge/Detachment)
cat <<'EOT' > /usr/local/bin/axiom-hardware-monitor
#!/bin/bash
# Monitor libinput for generic tablet-mode switch events
stdbuf -oL libinput debug-events | while read -r line; do
    if echo "\$line" | grep -q "tablet-mode state 1"; then
        /usr/local/bin/axiom-mode-toggle tablet
    elif echo "\$line" | grep -q "tablet-mode state 0"; then
        /usr/local/bin/axiom-mode-toggle laptop
    fi
done
EOT

# 3. Settings Shortcuts
cat <<EOT > /usr/share/applications/axiom-mode.desktop
[Desktop Entry]
Name=Device Mode
Exec=axiom-mode-toggle
Icon=input-tablet
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

# 4. Axiom Store PWAs
declare -A PWAS=( ["Calendar"]="https://calendar.google.com" ["Keep"]="https://keep.google.com" ["Meet"]="https://meet.google.com" ["Photos"]="https://photos.google.com" )
for NAME in "\${!PWAS[@]}"; do
    URL=\${PWAS[\$NAME]}
    echo -e "[Desktop Entry]\nName=\$NAME\nExec=google-chrome-stable --app=\$URL\nIcon=google-chrome\nType=Application\nCategories=AxiomStore;" > /usr/share/applications/axiom-\${NAME,,}.desktop
done

chmod +x /usr/local/bin/axiom-*

# --- USER DEFAULTS & UI ---
mkdir -p /etc/skel/.config/autostart

# Maliit keyboard for focus-aware input (Laptop or Tablet mode)
cat <<EOT > /etc/skel/.config/kwinrc
[Wayland]
InputMethod=/usr/share/applications/com.github.maliit.keyboard.desktop
EOT

# Default Taskbar and Applets
cat <<EOT > /etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc
[Panels][1]
Alignment=Center
Location=Bottom
Thickness=44
LengthMode=Fill
[Applets][2]
plugin=org.kde.plasma.taskmanager
Configuration=showOnlyCurrentDesktop:true;launchers=google-chrome.desktop,gmail.desktop,docs.desktop,drive.desktop,files.desktop,settings.desktop,org.kde.plasma-systemmonitor.desktop,org.kde.discover.desktop
EOT

# Register Background Monitor
echo -e "[Desktop Entry]\nExec=axiom-hardware-monitor\nType=Application\nName=Axiom Monitor" > /etc/skel/.config/autostart/axiom-monitor.desktop

# Final Cleanup to keep SquashFS size low
apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/*
EOF

# --- 4. PACKAGING ---
echo "--- Compressing File System (SquashFS) ---"
sudo umount -l "$ROOT/dev" "$ROOT/run" "$ROOT/proc" "$ROOT/sys" || true
sudo cp "$ROOT"/boot/vmlinuz-*-generic "$ISO_DIR/live/vmlinuz"
sudo cp "$ROOT"/boot/initrd.img-*-generic "$ISO_DIR/live/initrd"
sudo mksquashfs "$ROOT" output/AxiomOS.iso -comp xz
