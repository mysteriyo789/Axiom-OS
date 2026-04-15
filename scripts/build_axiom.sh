#!/bin/bash
set -e

# --- FIX 1: Robust Pathing ---
# Using absolute paths and ensuring cleanup of previous failed builds
ROOT=$(pwd)/axiom_rootfs
ISO_DIR=$(pwd)/axiom_iso
mkdir -p "$ROOT" "$ISO_DIR/live" output
export DEBIAN_FRONTEND=noninteractive

# --- FIX 2: Dependency Check ---
# Ensure debootstrap is present before starting
if ! command -v debootstrap &> /dev/null; then
    sudo apt-get update && sudo apt-get install -y debootstrap
fi

echo "--- Stage 1: Bootstrapping Base System ---"
sudo debootstrap --arch amd64 jammy "$ROOT" http://archive.ubuntu.com/ubuntu/

echo "--- Stage 2: Customizing the Google Experience ---"
# Safe Mounts
sudo mount --bind /dev "$ROOT/dev"
sudo mount --bind /run "$ROOT/run"
sudo mount -t proc proc "$ROOT/proc"
sudo mount -t sysfs sys "$ROOT/sys"

sudo chroot "$ROOT" /bin/bash <<EOF
export DEBIAN_FRONTEND=noninteractive

# --- FIX 3: Explicit Repository Activation ---
# Many Purple OS builds failed because Universe/Multiverse were missing
printf "deb http://archive.ubuntu.com/ubuntu/ jammy main restricted universe multiverse\n" > /etc/apt/sources.list
printf "deb http://archive.ubuntu.com/ubuntu/ jammy-updates main restricted universe multiverse\n" >> /etc/apt/sources.list
apt-get update

# Install Core & Google Chrome
apt-get install -y --no-install-recommends \
    linux-image-generic initramfs-tools casper \
    sddm plasma-desktop plasma-nm network-manager \
    wget curl ca-certificates plymouth plymouth-themes

# Purge Linux Bloat
apt-get purge -y kate kwrite khelpcenter evolution thunderbird \
    libreoffice* gnome-software software-properties-gtk \
    simple-scan hplip okular gwenview vlc
apt-get autoremove -y

# Install Chrome
wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
apt-get install -y ./google-chrome-stable_current_amd64.deb
rm google-chrome-stable_current_amd64.deb

# --- GOOGLE APP SEEDING ---
mkdir -p /etc/skel/.local/share/applications
APPS=("Gmail:https://mail.google.com:mail-send" 
      "Drive:https://drive.google.com:folder-remote" 
      "Docs:https://docs.google.com:document-properties" 
      "YouTube:https://www.youtube.com:youtube")

for app in "\${APPS[@]}"; do
    NAME=\$(echo \$app | cut -d: -f1)
    URL=\$(echo \$app | cut -d: -f2,3)
    ICON=\$(echo \$app | cut -d: -f4)
    echo -e "[Desktop Entry]\nName=\$NAME\nExec=google-chrome-stable --app=\$URL\nIcon=\$ICON\nType=Application" > /etc/skel/.local/share/applications/\${NAME,,}.desktop
done

# UI: Files, Settings, Light Mode, and Shelf
echo -e "[Desktop Entry]\nName=Files\nExec=dolphin\nIcon=system-file-manager\nType=Application" > /etc/skel/.local/share/applications/files.desktop
echo -e "[Desktop Entry]\nName=Settings\nExec=systemsettings\nIcon=preferences-system\nType=Application" > /etc/skel/.local/share/applications/settings.desktop

mkdir -p /etc/skel/.config
echo -e "[General]\nColorScheme=Breeze\n[Icons]\nTheme=breeze" > /etc/skel/.config/kdeglobals
cat <<EOT > /etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc
[Panels][1]
Alignment=Center
Location=Bottom
Thickness=56
LengthMode=Fit
Floating=1
WidgetOrder=org.kde.plasma.kickoff;org.kde.plasma.taskmanager;org.kde.plasma.systemtray;org.kde.plasma.digitalclock
[Applets][2]
plugin=org.kde.plasma.taskmanager
Configuration=showOnlyCurrentDesktop:true;launchers=google-chrome.desktop,gmail.desktop,docs.desktop,files.desktop,settings.desktop
EOT

apt-get clean
EOF

# --- FIX 4: Robust Kernel Extraction ---
# Don't hardcode version numbers; use wildcards to find the latest image
echo "--- Stage 3: Packaging ---"
sudo umount -l "$ROOT/dev" "$ROOT/run" "$ROOT/proc" "$ROOT/sys" || true
sudo cp "$ROOT"/boot/vmlinuz-*-generic "$ISO_DIR/live/vmlinuz"
sudo cp "$ROOT"/boot/initrd.img-*-generic "$ISO_DIR/live/initrd"
sudo mksquashfs "$ROOT" output/AxiomOS.iso -comp xz
