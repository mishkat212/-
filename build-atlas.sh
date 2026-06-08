#!/usr/bin/env bash
# ==============================================================================
# Atlas OS 3.0 "NEXUS" Build Script (Codespaces Ultimate Edition v2)
# Target: GitHub Codespaces (Ubuntu 22.04/24.04 host)
# ==============================================================================

set -euo pipefail

# --- الألوان لتنسيق المخرجات ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

msg_info() { echo -e "${BLUE}[i]${NC} $1"; }
msg_ok() { echo -e "${GREEN}[✓]${NC} $1"; }
msg_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
msg_err() { echo -e "${RED}[✗]${NC} $1"; }

# --- المتغيرات ومسارات العمل ---
PROJ_DIR="$(pwd)"
BUILD_DIR="/tmp/atlas-full-build"
CHROOT_DIR="${BUILD_DIR}/chroot"
IMAGE_DIR="${BUILD_DIR}/image"
# Up-to-date Debian keyring fetched from Debian (the host's bundled
# debian-archive-keyring is often outdated and lacks the Bookworm signing keys,
# which is the root cause of the "Couldn't execute /usr/bin/apt-key" failure).
KEYRING_HOST="${BUILD_DIR}/debian-archive-keyring.gpg"
KEYRING_CHROOT="/usr/share/keyrings/debian-archive-keyring.gpg"
DATE=$(date +%Y%m%d)
ISO_NAME="atlas-os-3.0-amd64-${DATE}.iso"
ISO_PATH="${PROJ_DIR}/${ISO_NAME}"

# --- قوائم الحزم والتطبيقات ---
BASE_PKGS="ca-certificates,apt-transport-https,gnupg,gpgv,debian-archive-keyring,curl,wget,linux-image-amd64,initramfs-tools,grub-pc-bin,grub-efi-amd64-bin,sudo,bash-completion,nano,vim,htop,neofetch,inxi,locales,dbus,systemd-sysv,network-manager,tzdata"
DESKTOP_PKGS="lxde xfce4 kde-standard sddm"
GAMING_PKGS="wine wine32 wine64 winetricks playonlinux lutris gamemode mesa-utils mesa-vulkan-drivers libvulkan1 libvulkan1:i386 libgl1-mesa-dri libgl1-mesa-dri:i386 supertuxkart extremetuxracer openarena xonotic retroarch pcsx2"
DEV_PKGS="git gitg build-essential gcc g++ make cmake python3 python3-pip python3-venv nodejs npm golang-go default-jdk ruby php php-cli sqlite3 vscodium geany meld docker.io podman"
CREATIVE_PKGS="blender kdenlive audacity gimp inkscape obs-studio darktable scribus ardour lmms"
SEC_DEBIAN_PKGS="nmap wireshark john hydra aircrack-ng sqlmap ettercap-graphical zaproxy gobuster dirb nikto recon-ng autopsy volatility binwalk foremost steghide hashcat crunch cewl"
SEC_KALI_PKGS="setoolkit bettercap metasploit-framework beef-xss"
SYS_PKGS="timeshift deja-dup clamav clamav-daemon rkhunter chkrootkit aide auditd gufw fail2ban dunst udiskie volumeicon-alsa hardinfo gnome-disk-utility testdisk grsync unattended-upgrades update-notifier flatpak plank arc-menu ulauncher"

# --- دوال البناء الأساسية ---

preflight() {
    msg_info "Running preflight checks..."
    if [[ "$EUID" -ne 0 ]]; then
        msg_err "This script must be run with sudo."
        exit 1
    fi

    if ! curl -Is https://deb.debian.org | head -n 1 | grep -q "200\|302"; then
        msg_err "No internet connection to Debian mirrors."
        exit 1
    fi
    msg_ok "Internet connectivity verified."

    local avail_kb=$(df -k /tmp | awk 'NR==2 {print $4}')
    if [[ "$avail_kb" -lt 18874368 ]]; then
        msg_err "Insufficient space in /tmp. Require >18GB, found $((avail_kb/1024/1024))GB."
        exit 1
    fi
    msg_ok "Storage space verified ($((avail_kb/1024/1024))GB available in /tmp)."
}

install_host_tools() {
    msg_info "Installing host dependencies..."
    export DEBIAN_FRONTEND=noninteractive

    apt-get update -qq
    # 'gpg' and 'dpkg-dev' are required so mmdebstrap can handle signed-by
    # keyrings and so we can extract the up-to-date keyring below.
    apt-get install -y -qq --no-install-recommends mmdebstrap squashfs-tools xorriso isolinux syslinux-efi \
        grub-pc-bin grub-efi-amd64-bin mtools dosfstools curl wget gpg dpkg-dev \
        debian-archive-keyring > /dev/null
    msg_ok "Host tools installed."
}

fetch_current_keyring() {
    # The debian-archive-keyring shipped with older Ubuntu/Codespaces hosts does
    # NOT contain the Debian 12 "Bookworm" signing keys. apt then fails to verify
    # the repository and falls back to the deprecated (and on newer hosts,
    # removed) apt-key binary -> "Couldn't execute /usr/bin/apt-key".
    # We download the current keyring straight from Debian to guarantee the
    # Bookworm keys are present.
    msg_info "Fetching up-to-date Debian archive keyring..."
    mkdir -p "${BUILD_DIR}/keyring-deb"
    local pool="http://deb.debian.org/debian/pool/main/d/debian-archive-keyring/"
    local deb
    deb=$(curl -fsSL "${pool}" | grep -oE 'debian-archive-keyring_[0-9.~a-z+]+_all\.deb' | sort -V | tail -n1)
    if [[ -z "${deb}" ]]; then
        msg_err "Could not determine latest debian-archive-keyring package."
        exit 1
    fi
    curl -fsSL -o "${BUILD_DIR}/keyring-deb/${deb}" "${pool}${deb}"
    dpkg-deb -x "${BUILD_DIR}/keyring-deb/${deb}" "${BUILD_DIR}/keyring-deb/extracted"
    cp "${BUILD_DIR}/keyring-deb/extracted/usr/share/keyrings/debian-archive-keyring.gpg" "${KEYRING_HOST}"
    msg_ok "Keyring ready: ${deb}"
}

clean_build() {
    msg_info "Cleaning temporary build directories..."
    umount -q "${CHROOT_DIR}/proc" || true
    umount -q "${CHROOT_DIR}/sys" || true
    umount -q "${CHROOT_DIR}/dev" || true
    rm -rf "${BUILD_DIR}"
    msg_ok "Cleanup complete."
}

chroot_exec() {
    chroot "${CHROOT_DIR}" /bin/bash -c "$1"
}

build_base() {
    msg_info "Bootstrapping base system with mmdebstrap (Debian Bookworm)..."
    mkdir -p "${CHROOT_DIR}"

    # Pass a FULL deb line with signed-by pointing at the up-to-date keyring.
    # mmdebstrap uses this line verbatim for the chroot's sources.list, so it
    # MUST contain the suite and components. This makes mmdebstrap's own initial
    # apt-get update verify with gpgv against the correct keyring and never
    # touch apt-key.
    mmdebstrap --variant=apt \
        --keyring="${KEYRING_HOST}" \
        --include="${BASE_PKGS}" \
        bookworm "${CHROOT_DIR}" \
        "deb [signed-by=${KEYRING_HOST}] http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware"
    msg_ok "Base system created."

    # --- Install the up-to-date keyring INTO the chroot and point sources at it ---
    # The bootstrap sources.list references the host keyring path, which won't
    # exist once the chroot is squashed. Rewrite it to an in-chroot path.
    msg_info "Setting up GPG keyring and apt sources (signed-by format)..."
    mkdir -p "${CHROOT_DIR}/usr/share/keyrings/"
    cp "${KEYRING_HOST}" "${CHROOT_DIR}${KEYRING_CHROOT}"

    cat << EOF > "${CHROOT_DIR}/etc/apt/sources.list"
deb [signed-by=${KEYRING_CHROOT}] http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb [signed-by=${KEYRING_CHROOT}] http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
deb [signed-by=${KEYRING_CHROOT}] http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
EOF

    # Remove any stale sources from mmdebstrap and cached apt lists
    rm -f "${CHROOT_DIR}/etc/apt/sources.list.d/"* 2>/dev/null || true
    rm -rf "${CHROOT_DIR}/var/lib/apt/lists/"*
    msg_ok "Keyring and sources configured."

    msg_info "Configuring chroot mounts..."
    mount -t proc none "${CHROOT_DIR}/proc"
    mount -t sysfs none "${CHROOT_DIR}/sys"
    mount -o bind /dev "${CHROOT_DIR}/dev"

    msg_info "Configuring system settings..."
    chroot_exec "echo 'atlas-nexus' > /etc/hostname"
    chroot_exec "echo '127.0.0.1 localhost atlas-nexus' > /etc/hosts"
    chroot_exec "export DEBIAN_FRONTEND=noninteractive && dpkg-reconfigure -f noninteractive tzdata"

    # Now apt-get update uses signed-by + the correct keyring; apt-key is never called
    chroot_exec "apt-get update"
    msg_ok "Base system configured and apt updated successfully."
}

setup_user_and_desktops() {
    msg_info "Creating default user 'atlas'..."
    chroot_exec "useradd -m -s /bin/bash atlas"
    chroot_exec "echo 'atlas:atlas' | chpasswd"
    chroot_exec "echo 'atlas ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/atlas"

    msg_info "Installing Desktop Environments..."
    chroot_exec "export DEBIAN_FRONTEND=noninteractive && apt-get install -y --no-install-recommends ${DESKTOP_PKGS}"

    msg_info "Creating RAM-based Desktop Auto-Selector..."
    cat << 'EOF' > "${CHROOT_DIR}/etc/profile.d/desktop-autoselect.sh"
#!/bin/bash
if [[ -z "$DISPLAY" && $(tty) == /dev/tty1 ]]; then
    TOTAL_RAM=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    if [[ "$TOTAL_RAM" -lt 2000000 ]]; then
        exec startlxde
    elif [[ "$TOTAL_RAM" -lt 4000000 ]]; then
        exec startxfce4
    else
        exec startplasma-x11
    fi
fi
EOF
    chmod +x "${CHROOT_DIR}/etc/profile.d/desktop-autoselect.sh"
    msg_ok "Desktops and auto-selector configured."
}

install_packages() {
    local build_type=$1
    msg_info "Adding i386 architecture for gaming/Wine..."
    chroot_exec "dpkg --add-architecture i386"
    chroot_exec "apt-get update"

    msg_info "Installing System, Gaming, Creative, and Dev packages..."
    chroot_exec "export DEBIAN_FRONTEND=noninteractive && apt-get install -y --no-install-recommends ${SYS_PKGS} ${GAMING_PKGS} ${CREATIVE_PKGS} ${DEV_PKGS}"

    msg_info "Installing standard Debian Security Tools..."
    chroot_exec "export DEBIAN_FRONTEND=noninteractive && apt-get install -y --no-install-recommends ${SEC_DEBIAN_PKGS}"

    if [[ "$build_type" == "full" ]]; then
        msg_warn "Adding Kali Repository for specialized tools (Metasploit, Beef)..."

        # Download and store the Kali keyring using the modern signed-by approach
        chroot_exec "wget -q -O /tmp/kali-archive-key.asc https://archive.kali.org/archive-key.asc"
        chroot_exec "gpg --dearmor -o /usr/share/keyrings/kali-archive-keyring.gpg < /tmp/kali-archive-key.asc"
        chroot_exec "rm -f /tmp/kali-archive-key.asc"

        # Use signed-by to reference the keyring — apt-key is never invoked
        chroot_exec "echo 'deb [signed-by=/usr/share/keyrings/kali-archive-keyring.gpg] http://http.kali.org/kali kali-rolling main contrib non-free' > /etc/apt/sources.list.d/kali.list"

        # APT Pinning to protect the system from package conflicts
        cat << 'EOF' > "${CHROOT_DIR}/etc/apt/preferences.d/kali"
Package: *
Pin: release a=kali-rolling
Pin-Priority: 50
EOF
        chroot_exec "apt-get update"
        chroot_exec "export DEBIAN_FRONTEND=noninteractive && apt-get install -y --no-install-recommends -t kali-rolling ${SEC_KALI_PKGS} || true"
        msg_ok "Kali tools processed."
    fi

    msg_info "Adding Flathub remote..."
    chroot_exec "flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo"
}

apply_themes() {
    msg_info "Installing Fluent KDE & Icon Themes..."
    chroot_exec "export DEBIAN_FRONTEND=noninteractive && apt-get install -y git make"
    chroot_exec "git clone https://github.com/vinceliuice/Fluent-kde-theme.git /tmp/fluent-kde"
    chroot_exec "git clone https://github.com/vinceliuice/Fluent-icon-theme.git /tmp/fluent-icon"
    chroot_exec "cd /tmp/fluent-kde && ./install.sh"
    chroot_exec "cd /tmp/fluent-icon && ./install.sh -a"
    chroot_exec "rm -rf /tmp/fluent-kde /tmp/fluent-icon"

    msg_info "Applying mock Windows 11 Plasma layout script..."
    cat << 'EOF' > "${CHROOT_DIR}/usr/local/bin/apply-win11-layout"
#!/bin/bash
kwriteconfig5 --file kdeglobals --group General --key ColorScheme "FluentLight"
kwriteconfig5 --file kdeglobals --group Icons --key Theme "Fluent"
qdbus org.kde.KWin /KWin reconfigure
EOF
    chmod +x "${CHROOT_DIR}/usr/local/bin/apply-win11-layout"
    msg_ok "Themes installed."
}

integrate_custom_apps() {
    msg_info "Checking for custom apps in ${PROJ_DIR}/apps..."
    if [[ -d "${PROJ_DIR}/apps" ]]; then
        for py_file in "${PROJ_DIR}/apps"/*.py; do
            if [[ -f "$py_file" ]]; then
                local base_name=$(basename "$py_file" .py)
                msg_info "Integrating custom app: $base_name"
                cp "$py_file" "${CHROOT_DIR}/usr/local/bin/${base_name}"
                chmod +x "${CHROOT_DIR}/usr/local/bin/${base_name}"

                cat << EOF > "${CHROOT_DIR}/usr/share/applications/${base_name}.desktop"
[Desktop Entry]
Name=${base_name}
Exec=/usr/local/bin/${base_name}
Icon=utilities-terminal
Terminal=false
Type=Application
Categories=Utility;
EOF
            fi
        done
        msg_ok "Custom apps integrated."
    else
        msg_warn "No './apps' directory found. Skipping custom apps."
    fi
}

build_iso() {
    msg_info "Preparing ISO filesystem structure..."
    mkdir -p "${IMAGE_DIR}/live"
    mkdir -p "${IMAGE_DIR}/isolinux"
    mkdir -p "${IMAGE_DIR}/EFI/BOOT"
    mkdir -p "${IMAGE_DIR}/boot/grub/x86_64-efi"

    msg_info "Extracting Kernel and Initrd..."
    cp "${CHROOT_DIR}"/boot/vmlinuz-* "${IMAGE_DIR}/live/vmlinuz"
    cp "${CHROOT_DIR}"/boot/initrd.img-* "${IMAGE_DIR}/live/initrd.img"

    msg_info "Cleaning up chroot before squashing..."
    chroot_exec "apt-get clean"
    rm -f "${CHROOT_DIR}/var/lib/dbus/machine-id"
    umount -q "${CHROOT_DIR}/proc" || true
    umount -q "${CHROOT_DIR}/sys" || true
    umount -q "${CHROOT_DIR}/dev" || true

    msg_info "Compressing filesystem (mksquashfs) - this will take a while..."
    mksquashfs "${CHROOT_DIR}" "${IMAGE_DIR}/live/filesystem.squashfs" -comp xz -b 1M -e boot var/cache/apt/archives

    msg_info "Configuring ISOLINUX (BIOS)..."
    cp /usr/lib/ISOLINUX/isolinux.bin "${IMAGE_DIR}/isolinux/"
    cp /usr/lib/syslinux/modules/bios/{ldlinux.c32,libcom32.c32,libutil.c32,vesamenu.c32} "${IMAGE_DIR}/isolinux/" || true

    cat << 'EOF' > "${IMAGE_DIR}/isolinux/isolinux.cfg"
UI vesamenu.c32
TIMEOUT 100
DEFAULT live
MENU TITLE Atlas OS 3.0 "NEXUS"

LABEL live
  MENU LABEL Boot Atlas OS 3.0 (RAM Auto-Detect)
  LINUX /live/vmlinuz
  APPEND initrd=/live/initrd.img boot=live quiet splash
EOF

    msg_info "Configuring GRUB (UEFI)..."
    cat << 'EOF' > "${IMAGE_DIR}/boot/grub/grub.cfg"
search --set=root --file /live/vmlinuz
insmod all_video

menuentry "Boot Atlas OS 3.0 (RAM Auto-Detect)" {
    linux /live/vmlinuz boot=live quiet splash
    initrd /live/initrd.img
}
EOF

    msg_info "Building EFI Image..."
    grub-mkstandalone --format=x86_64-efi --out="${IMAGE_DIR}/EFI/BOOT/BOOTX64.EFI" --locales="" --fonts="" "boot/grub/grub.cfg=${IMAGE_DIR}/boot/grub/grub.cfg"
    dd if=/dev/zero of="${IMAGE_DIR}/efi.img" bs=1M count=5
    mkfs.vfat "${IMAGE_DIR}/efi.img"
    mmd -i "${IMAGE_DIR}/efi.img" ::/EFI ::/EFI/BOOT
    mcopy -i "${IMAGE_DIR}/efi.img" "${IMAGE_DIR}/EFI/BOOT/BOOTX64.EFI" ::/EFI/BOOT/

    msg_info "Generating Hybrid ISO using xorriso..."
    cd "${IMAGE_DIR}"
    xorriso -as mkisofs \
        -r -V "ATLAS_NEXUS" \
        -J -l -b isolinux/isolinux.bin \
        -c isolinux/boot.cat \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
        -eltorito-alt-boot \
        -e efi.img \
        -no-emul-boot -isohybrid-gpt-basdat \
        -o "${ISO_PATH}" .

    msg_ok "ISO build complete! Saved to: ${ISO_PATH}"
    ls -lh "${ISO_PATH}"
}

# --- القائمة الرئيسية للمستخدم ---

clear
echo -e "${BLUE}==========================================${NC}"
echo -e "${GREEN}      Atlas OS 3.0 'NEXUS' Builder      ${NC}"
echo -e "${BLUE}==========================================${NC}"
echo "Select build type:"
echo " [1] Full build (All packages + Kali Sec Tools)"
echo " [2] Light build (Skip Kali Sec Tools)"
echo " [0] Clean temporary build files"
echo " [Q] Quit"
echo ""
read -p "Enter choice: " choice

case $choice in
    1)
        preflight
        install_host_tools
        clean_build
        fetch_current_keyring
        build_base
        setup_user_and_desktops
        install_packages "full"
        apply_themes
        integrate_custom_apps
        build_iso
        ;;
    2)
        preflight
        install_host_tools
        clean_build
        fetch_current_keyring
        build_base
        setup_user_and_desktops
        install_packages "light"
        apply_themes
        integrate_custom_apps
        build_iso
        ;;
    0)
        clean_build
        ;;
    Q|q)
        exit 0
        ;;
    *)
        msg_err "Invalid choice."
        exit 1
        ;;
esac
