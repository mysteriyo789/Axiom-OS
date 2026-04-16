#!/bin/bash
set -e

# --- 1. Environment & Path Fixes ---
ROOT=$(pwd)/axiom_rootfs
ISO_DIR=$(pwd)/axiom_iso
mkdir -p "$ROOT" "$ISO_DIR/live" output
export DEBIAN_FRONTEND=noninteractive

# --- 2. Stage 1: Fast Bootstrapping ---
echo "--- Stage 1: Bootstrapping ---"
# We removed --variant=minbase to ensure basic tools like 'find' and 'wget' are present
sudo debootstrap --arch amd64 jammy "$ROOT" http://azure.archive.ubuntu.com/ubuntu/

# --- 3. Stage 2: Customization ---
echo "--- Stage 2: Branding & Google Experience ---"
sudo mount --bind /dev "$ROOT/dev"
sudo mount --bind /run "$ROOT/run"
sudo mount -t proc proc "$ROOT/proc"
sudo mount -t sysfs sys "$ROOT/sys"

sudo chroot "$ROOT" /bin/bash <<EOF
export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C

# Use Azure mirrors inside chroot
printf "deb http://azure.archive.ubuntu.com/ubuntu/ jammy main restricted universe multiverse\n" > /etc/apt/sources.list
printf "deb http://azure.archive.ubuntu.com/ubuntu/ jammy-updates main restricted universe multiverse\n" >> /etc/apt/sources.list
apt-get update

# Install Essential Tools first
apt-get install -y wget ca-certificates

# Install Kernel, Desktop, and Installer
apt-get install -y --yes -o Dpkg::Options::="--force-confold" --no-install-recommends \
    linux-generic initramfs-tools casper \
    sddm plasma-desktop plasma-nm network-manager \
    plymouth plymouth-themes plymouth-label \
    ubiquity ubiquity-frontend-gtk ubiquity-slideshow-ubuntu

# Install Google Chrome
wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
apt-get install -y ./google-chrome-stable_current_amd64.deb
rm google-chrome-stable_current_amd64.deb

# PURGE LINUX BLOAT
apt-get purge -y kate kwrite khelpcenter evolution thunderbird \
    libreoffice* gnome-software software-properties-gtk \
    simple-scan hplip okular gwenview vlc
apt-get autoremove -y

# CUSTOM BOOT SPLASH: "Axiom OS"
mkdir -p /usr/share/plymouth/themes/axiom
cat <<EOT > /usr/share/plymouth/themes/axiom/axiom.plymouth
[Plymouth Theme]
Name=Axiom OS
ModuleName=script
[script]
ImageDir=/usr/share/plymouth/themes/axiom
ScriptFile=/usr/share/plymouth/themes/axiom/axiom.script
EOT

cat <<EOT > /usr/share/plymouth/themes/axiom/axiom.script
Window.SetBackgroundTopColor(0, 0, 0);
Window.SetBackgroundBottomColor(0, 0, 0);
label = Image.Text("Axiom OS", 1, 1, 1);
sprite = Sprite(label);
sprite.SetX(Window.GetWidth() / 2 - label.GetWidth() / 2);
sprite.SetY(Window.GetHeight() / 2 - label.GetHeight() / 2);
EOT
update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth /usr/share/plymouth/themes/axiom/axiom.plymouth 100
echo 1 | update-alternatives --config default.plymouth
update-initramfs -u

# GOOGLE APP SUITE & UI RENAMING
mkdir -p /etc/skel/.local/share/applications
declare -A G_APPS=( ["Gmail"]="https://mail.google.com" ["Docs"]="https://docs.google.com" ["Drive"]="https://drive.google.com" ["YouTube"]="https://www.youtube.com" )
for NAME in "\${!G_APPS[@]}"; do
    URL=\${G_APPS[\$NAME]}
    echo -e "[Desktop Entry]\nName=\$NAME\nExec=google-chrome-stable --app=\$URL\nIcon=google-chrome\nType=Application" > /etc/skel/.local/share/applications/\${NAME,,}.desktop
done
echo -e "[Desktop Entry]\nName=Files\nExec=dolphin\nIcon=system-file-manager\nType=Application" > /etc/skel/.local/share/applications/files.desktop
echo -e "[Desktop Entry]\nName=Settings\nExec=systemsettings\nIcon=preferences-system\nType=Application" > /etc/skel/.local/share/applications/settings.desktop

# DEFAULT LIGHT MODE & SHELF
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
Configuration=showOnlyCurrentDesktop:true;launchers=google-chrome.desktop,gmail.desktop,docs.desktop,drive.desktop,files.desktop,settings.desktop
EOT

# AUTO-START INSTALLER
mkdir -p /etc/skel/.config/autostart
cp /usr/share/applications/ubiquity.desktop /etc/skel/.config/autostart/

apt-get clean
EOF

# --- 4. Packaging ---
echo "--- Stage 3: Packaging ISO ---"
sudo umount -l "$ROOT/dev" "$ROOT/run" "$ROOT/proc" "$ROOT/sys" || true
# Now that linux-generic is installed, these files will exist:
sudo cp "$ROOT"/boot/vmlinuz-*-generic "$ISO_DIR/live/vmlinuz"
sudo cp "$ROOT"/boot/initrd.img-*-generic "$ISO_DIR/live/initrd"
sudo mksquashfs "$ROOT" output/AxiomOS.iso -comp xz
