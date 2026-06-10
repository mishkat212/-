#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║              █████╗ ████████╗██╗      █████╗ ███████╗                      ║
# ║             ██╔══██╗╚══██╔══╝██║     ██╔══██╗██╔════╝                      ║
# ║             ███████║   ██║   ██║     ███████║███████╗                      ║
# ║             ██╔══██║   ██║   ██║     ██╔══██║╚════██║                      ║
# ║             ██║  ██║   ██║   ███████╗██║  ██║███████║                      ║
# ║             ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚══════╝                      ║
# ║                                                                            ║
# ║              ATLAS LINUX  ·  نظام أطلس لينكس                              ║
# ║       Gaming | Design | Office | Security | Arabic & English               ║
# ║                                                                            ║
# ║  الإصدار : 1.0.0  |  القاعدة: Arch Linux  |  المعمارية: x86_64            ║
# ║  الواجهات: KDE Plasma · XFCE · LXDE  (تُختار تلقائياً حسب الجهاز)         ║
# ║  المتطلبات: GitHub Codespaces / Ubuntu 22.04+ / Arch Linux                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
#  الاستخدام / Usage:
#    chmod +x atlas-linux-build.sh
#    sudo bash atlas-linux-build.sh [--mode iso|chroot|manifest]
#
#  في GitHub Codespaces:
#    bash atlas-linux-build.sh --mode manifest
#
#  يُصلح الأخطاء تلقائياً ويتكيّف مع البيئة المتاحة
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail
IFS=$'\n\t'

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# [0]  متغيرات عامة  /  Global Variables
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
readonly ATLAS_VERSION="1.0.0"
readonly ATLAS_CODENAME="Phoenix"
readonly ATLAS_ARCH="x86_64"
readonly ATLAS_DATE="$(date +%Y%m%d)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_MODE="${1:-}"                         # --mode iso | chroot | manifest
BUILD_DIR="${ATLAS_BUILD_DIR:-/tmp/atlas-build}"
OUT_DIR="${ATLAS_OUT_DIR:-$SCRIPT_DIR/atlas-output}"
LOG_FILE="$OUT_DIR/build-${ATLAS_DATE}.log"
MANIFEST_FILE="$OUT_DIR/atlas-packages.manifest"
APPS_DIR="${ATLAS_APPS_DIR:-$SCRIPT_DIR/apps}"

# اكتشاف البيئة  /  Detect environment
IS_CODESPACES=false
IS_ARCH=false
IS_UBUNTU=false
IS_ROOT=false

[[ "${CODESPACES:-}" == "true" || -n "${GITHUB_CODESPACE_TOKEN:-}" ]] && IS_CODESPACES=true
[[ -f /etc/arch-release ]] && IS_ARCH=true
[[ -f /etc/lsb-release ]] && grep -qi ubuntu /etc/lsb-release && IS_UBUNTU=true
[[ $EUID -eq 0 ]] && IS_ROOT=true

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# [1]  ألوان وأدوات سجل  /  Colors & Logging
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'
C='\033[0;36m'; W='\033[1;37m'; P='\033[0;35m'; N='\033[0m'

_log()     { local lvl="$1"; shift; echo -e "${lvl}[ATLAS]${N} $*" | tee -a "$LOG_FILE" 2>/dev/null || true; }
log()      { _log "$G"  "$*"; }
warn()     { _log "$Y"  "⚠  $*"; }
err()      { _log "$R"  "✗  $*"; }
info()     { _log "$C"  "ℹ  $*"; }
ok()       { _log "$G"  "✓  $*"; }
section()  {
  echo -e "\n${P}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}" | tee -a "$LOG_FILE" 2>/dev/null || true
  echo -e "${W}  ◆  $*${N}" | tee -a "$LOG_FILE" 2>/dev/null || true
  echo -e "${P}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}\n" | tee -a "$LOG_FILE" 2>/dev/null || true
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# [2]  معالجة الأخطاء التلقائية  /  Auto Error Recovery
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ERRORS_LOG=()

auto_fix() {
  # يحاول إصلاح الخطأ تلقائياً ويسجله إن لم يُصلح
  local ctx="$1"; shift
  warn "محاولة إصلاح تلقائي: $ctx"
  case "$ctx" in
    pkg_install)
      # تحديث قواعد البيانات ثم إعادة المحاولة
      if $IS_ARCH && $IS_ROOT; then
        pacman -Sy --noconfirm 2>/dev/null || true
      elif $IS_UBUNTU || $IS_CODESPACES; then
        apt-get update -qq 2>/dev/null || true
      fi
      ;;
    archiso_missing)
      if $IS_ARCH && $IS_ROOT; then
        pacman -S --noconfirm archiso 2>/dev/null || true
      fi
      ;;
    space)
      warn "مساحة منخفضة – تنظيف الكاش..."
      if $IS_ARCH && $IS_ROOT; then
        pacman -Sc --noconfirm 2>/dev/null || true
      elif $IS_UBUNTU || $IS_CODESPACES; then
        apt-get clean 2>/dev/null || true
        apt-get autoremove -y 2>/dev/null || true
      fi
      ;;
    *) warn "لا يوجد إصلاح تلقائي لـ: $ctx" ;;
  esac
}

trap_err() {
  local line=$1 cmd=$2
  err "خطأ في السطر $line: $cmd"
  ERRORS_LOG+=("Line $line: $cmd")
  # لا نوقف التنفيذ – نكمل ونسجل
  return 0
}
trap 'trap_err $LINENO "$BASH_COMMAND"' ERR

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# [3]  الشعار  /  Banner
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
show_banner() {
  clear 2>/dev/null || true
  echo -e "${B}"
  cat <<'BANNER'
   ╔══════════════════════════════════════════════════════════════╗
   ║   █████╗ ████████╗██╗      █████╗ ███████╗                 ║
   ║  ██╔══██╗╚══██╔══╝██║     ██╔══██╗██╔════╝                 ║
   ║  ███████║   ██║   ██║     ███████║███████╗                 ║
   ║  ██╔══██║   ██║   ██║     ██╔══██║╚════██║                 ║
   ║  ██║  ██║   ██║   ███████╗██║  ██║███████║                 ║
   ║  ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚══════╝                 ║
   ║                                                            ║
   ║        نظام أطلس لينكس · Atlas Linux v1.0.0               ║
   ║   Gaming · Design · Office · Security · AR+EN              ║
   ╚══════════════════════════════════════════════════════════════╝
BANNER
  echo -e "${N}"
  echo -e "${C}  بيئة التشغيل : $(uname -s) $(uname -r)${N}"
  echo -e "${C}  Codespaces   : $IS_CODESPACES${N}"
  echo -e "${C}  Arch Linux   : $IS_ARCH${N}"
  echo -e "${C}  Root         : $IS_ROOT${N}"
  echo -e "${C}  الوضع        : ${BUILD_MODE:-auto}${N}"
  echo ""
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# [4]  إعداد الدلائل  /  Setup Directories
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
setup_dirs() {
  mkdir -p "$OUT_DIR" "$BUILD_DIR" "$APPS_DIR"
  touch "$LOG_FILE"
  ok "الدلائل جاهزة: $OUT_DIR"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# [5]  اكتشاف وضع البناء  /  Detect Build Mode
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
detect_build_mode() {
  # تحليل الوسيط إن وُجد
  if [[ "$BUILD_MODE" == "--mode" ]]; then BUILD_MODE="${2:-auto}"; fi
  case "${BUILD_MODE}" in
    *iso*)     BUILD_MODE="iso" ;;
    *chroot*)  BUILD_MODE="chroot" ;;
    *manifest*)BUILD_MODE="manifest" ;;
    *)
      # اكتشاف تلقائي
      if $IS_CODESPACES; then
        BUILD_MODE="manifest"
        info "GitHub Codespaces → وضع manifest (توليد قوائم الحزم + ملفات الإعداد)"
      elif $IS_ARCH && $IS_ROOT; then
        BUILD_MODE="iso"
        info "Arch Linux + root → وضع iso (بناء صورة ISO كاملة)"
      else
        BUILD_MODE="manifest"
        info "بيئة غير Arch → وضع manifest"
      fi
      ;;
  esac
  ok "وضع البناء: $BUILD_MODE"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# [6]  فحص وتثبيت متطلبات البناء  /  Check & Install Build Deps
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
install_build_deps() {
  section "التحقق من متطلبات البناء"

  if $IS_CODESPACES || $IS_UBUNTU; then
    info "بيئة Ubuntu/Codespaces – تثبيت أدوات المساعدة..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq 2>/dev/null || auto_fix pkg_install
    apt-get install -y -qq \
      curl wget git jq python3 python3-pip \
      squashfs-tools xorriso dosfstools \
      debootstrap arch-install-scripts \
      tree unzip zip p7zip-full \
      2>/dev/null || auto_fix pkg_install
    ok "أدوات Ubuntu/Codespaces جاهزة"

  elif $IS_ARCH && $IS_ROOT; then
    info "بيئة Arch Linux – تثبيت archiso..."
    pacman -Sy --noconfirm 2>/dev/null || auto_fix pkg_install
    local DEPS=(archiso git curl wget squashfs-tools libisoburn dosfstools)
    for d in "${DEPS[@]}"; do
      pacman -Q "$d" &>/dev/null || pacman -S --noconfirm "$d" 2>/dev/null || auto_fix pkg_install
    done
    ok "أدوات Arch جاهزة"

  else
    warn "لم يُتعرَّف على البيئة – وضع manifest فقط"
    BUILD_MODE="manifest"
  fi
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# [7]  كتشاف موارد الجهاز  /  Hardware Detection for Auto Desktop
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# القاعدة (تُطبَّق في أول تشغيل للنظام عبر سكريبت atlas-first-boot.sh) :
#   RAM >= 8GB  → KDE Plasma  (أغنى تجربة، ثيم Windows 11)
#   RAM 4-8GB  → XFCE        (متوازنة ، ثيم Windows 11 خفيف)
#   RAM < 4GB  → LXDE        (خفيف جداً)

generate_auto_desktop_script() {
  section "توليد سكريبت اختيار الواجهة التلقائي"

  cat > "$OUT_DIR/atlas-first-boot.sh" << 'FIRSTBOOT'
#!/usr/bin/env bash
# atlas-first-boot.sh — يُنفَّذ تلقائياً عند أول تشغيل للنظام
# يختار بيئة سطح المكتب حسب موارد الجهاز

set -euo pipefail

LOG=/var/log/atlas-first-boot.log
exec >> "$LOG" 2>&1
echo "[$(date)] Atlas First-Boot: بدء اكتشاف الجهاز..."

# ─── قراءة RAM ───────────────────────────────────────────────
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_RAM_GB=$(( TOTAL_RAM_KB / 1024 / 1024 ))

# ─── قراءة عدد الأنوية ────────────────────────────────────────
CPU_CORES=$(nproc 2>/dev/null || echo 2)

# ─── قراءة GPU ────────────────────────────────────────────────
GPU_INFO=$(lspci 2>/dev/null | grep -iE "VGA|3D|Display" | head -1 || echo "unknown")

echo "RAM: ${TOTAL_RAM_GB}GB | CPU Cores: $CPU_CORES | GPU: $GPU_INFO"

# ─── اختيار الواجهة ──────────────────────────────────────────
if (( TOTAL_RAM_GB >= 8 )); then
  SELECTED_DE="kde"
  DM="sddm"
  echo "✓ RAM >= 8GB → KDE Plasma + SDDM"
elif (( TOTAL_RAM_GB >= 4 )); then
  SELECTED_DE="xfce"
  DM="lightdm"
  echo "✓ RAM 4-8GB → XFCE + LightDM"
else
  SELECTED_DE="lxde"
  DM="lxdm"
  echo "✓ RAM < 4GB → LXDE + LXDM"
fi

# ─── تفعيل مدير عرض الشاشة ───────────────────────────────────
systemctl disable sddm lightdm lxdm gdm 2>/dev/null || true
systemctl enable "$DM" 2>/dev/null && echo "✓ فعّلت $DM"

# ─── حفظ الاختيار لجلسات المستقبل ──────────────────────────
echo "$SELECTED_DE" > /etc/atlas/default-de
echo "$DM"          > /etc/atlas/default-dm

# ─── إعدادات أداء خاصة بالواجهة ─────────────────────────────
case "$SELECTED_DE" in
  kde)
    # تفعيل Compositor Wayland + تأثيرات كاملة
    mkdir -p /etc/skel/.config/kwinrc
    cat > /etc/skel/.config/kwinrc << 'KDE_CFG'
[Compositing]
Backend=OpenGL
Enabled=true
GLColorCorrection=false
GLPreferBufferSwap=a
GLTextureFilter=2
HiddenPreviews=5
OpenGLIsUnsafe=false
WindowsBlockCompositing=true
XRenderSmoothScale=false
KDE_CFG
    ;;
  xfce)
    # تعطيل Compositor للأداء على الأجهزة المتوسطة
    mkdir -p /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml
    cat > /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml << 'XFCE_CFG'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="use_compositing" type="bool" value="false"/>
    <property name="vblank_mode" type="string" value="off"/>
  </property>
</channel>
XFCE_CFG
    ;;
  lxde)
    # تقليل التأثيرات إلى الحد الأدنى
    mkdir -p /etc/skel/.config/openbox
    cat > /etc/skel/.config/openbox/lxde-rc.xml << 'LXDE_CFG'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config>
  <applications/>
</openbox_config>
LXDE_CFG
    ;;
esac

# ─── تطبيق إعدادات عربي/إنجليزي ─────────────────────────────
localectl set-locale LANG=en_US.UTF-8 2>/dev/null || true
localectl set-x11-keymap "us,ar" pc105 "" "grp:alt_shift_toggle" 2>/dev/null || true

echo "[$(date)] Atlas First-Boot: اكتمل – DE: $SELECTED_DE"
FIRSTBOOT

  chmod +x "$OUT_DIR/atlas-first-boot.sh"
  ok "سكريبت اختيار الواجهة التلقائي: atlas-first-boot.sh"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# [8]  توليد قائمة الحزم الكاملة  /  Generate Complete Package Manifest
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
generate_package_manifest() {
  section "توليد قائمة الحزم الشاملة"
  : > "$MANIFEST_FILE"

  cat >> "$MANIFEST_FILE" << 'MANIFEST'
# ══════════════════════════════════════════════════════════════════════════════
#  Atlas Linux v1.0.0 — قائمة الحزم الكاملة / Complete Package Manifest
#  القاعدة: Arch Linux + AUR + BlackArch
#  الملف: atlas-packages.manifest
# ══════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────
# §01  النواة وقلب النظام  /  Kernel & Core System
# ─────────────────────────────────────────────────────────────
linux-zen                    # نواة محسّنة للغيمينغ وزمن الاستجابة
linux-zen-headers
linux-lts                    # نواة مستقرة طويلة الأمد
linux-lts-headers
linux-firmware               # كل firmware الأجهزة
linux-firmware-whence
dkms                         # بناء وحدات Kernel ديناميكياً
kmod
mkinitcpio
mkinitcpio-archiso
mkinitcpio-nfs-utils

# Bootloader
grub
efibootmgr
os-prober                    # لاكتشاف ويندوز تلقائياً
grub-customizer              # واجهة رسومية لـ GRUB

# Microcode – تحديثات أمان المعالج
amd-ucode
intel-ucode

# ─────────────────────────────────────────────────────────────
# §02  نظام الملفات  /  Filesystems
# ─────────────────────────────────────────────────────────────
btrfs-progs                  # نظام ملفات حديث مع snapshots
e2fsprogs                    # ext2/3/4
ntfs-3g                      # قراءة/كتابة NTFS (أقراص ويندوز)
exfatprogs                   # exFAT لبطاقات الذاكرة
dosfstools                   # FAT12/16/32
f2fs-tools                   # Flash-Friendly FS
xfsprogs                     # XFS
jfsutils                     # JFS
reiserfsprogs                # ReiserFS
mtools                       # أدوات FAT
gptfdisk                     # gdisk لأقراص GPT
parted                       # تقسيم الأقراص
gparted                      # واجهة رسومية لـ parted
gnome-disk-utility            # أداة الأقراص الرسومية
kdepartitionmanager          # مدير أقراص KDE

# ─────────────────────────────────────────────────────────────
# §03  إدارة الأجهزة  /  Hardware Management
# ─────────────────────────────────────────────────────────────
udev
hwdetect
hwinfo                       # معلومات مفصّلة الأجهزة
lshw                         # قائمة الأجهزة
lshw-gtk                     # واجهة رسومية
dmidecode                    # معلومات BIOS/UEFI
hdparm                       # ضبط الأقراص
smartmontools                # مراقبة صحة الأقراص (SMART)
nvme-cli                     # أدوات NVMe
gsmartcontrol                # واجهة رسومية SMART

# معالج / CPU
cpupower                     # إدارة تردد المعالج
thermald                     # إدارة الحرارة
lm_sensors                   # قراءة مستشعرات الحرارة
stress                       # اختبار الإجهاد
stress-ng
s-tui                        # مراقبة تفاعلية

# GPU – بطاقات الشاشة
mesa                         # OpenGL مفتوح المصدر
mesa-utils
vulkan-radeon                # AMD Vulkan
vulkan-intel                 # Intel Vulkan
vulkan-icd-loader
vulkan-tools
lib32-mesa                   # مكتبات 32-bit
lib32-vulkan-radeon
lib32-vulkan-intel
lib32-vulkan-icd-loader
xf86-video-amdgpu            # AMD GPU driver
xf86-video-intel             # Intel GPU driver
xf86-video-nouveau           # Nouveau (NVIDIA مفتوح)
xf86-video-vesa              # VESA fallback
xf86-video-fbdev             # Framebuffer
nvidia                       # NVIDIA proprietary
nvidia-lts
nvidia-utils
lib32-nvidia-utils
nvidia-settings              # لوحة تحكم NVIDIA
nvtop                        # مراقبة GPU مثل htop
radeontop                    # مراقبة AMD GPU

# ─────────────────────────────────────────────────────────────
# §04  الصوت  /  Audio
# ─────────────────────────────────────────────────────────────
pipewire                     # خادم الصوت الحديث
pipewire-alsa
pipewire-pulse               # توافق PulseAudio
pipewire-jack                # توافق JACK (استوديو)
wireplumber                  # مدير جلسات PipeWire
alsa-utils                   # أدوات ALSA
alsa-firmware
alsa-plugins
pavucontrol                  # لوحة تحكم PulseAudio/Pipewire
helvum                       # Graph لتوصيل تدفقات الصوت
easyeffects                  # معالجة صوت متقدمة

# ─────────────────────────────────────────────────────────────
# §05  الشبكة  /  Network
# ─────────────────────────────────────────────────────────────
networkmanager               # إدارة الشبكات
network-manager-applet       # أيقونة شريط المهام
nm-connection-editor         # محرر الاتصالات
wpa_supplicant               # WiFi WPA/WPA2
wireless_tools
iw                           # أدوات WiFi
iwd                          # iNet Wireless Daemon
dhcpcd
dhclient
nss-mdns                     # mDNS/Bonjour
avahi                        # اكتشاف الشبكة المحلية
avahi-ui-tools
openssh                      # SSH عميل/خادم
openssl

# VPN
openvpn
networkmanager-openvpn
wireguard-tools
networkmanager-wireguard

# بلوتوث
bluez
bluez-utils
blueman                      # مدير بلوتوث رسومي

# ─────────────────────────────────────────────────────────────
# §06  سطح المكتب X11/Wayland  /  Display Server
# ─────────────────────────────────────────────────────────────
xorg
xorg-server
xorg-apps
xorg-xinit
xorg-xrandr
xorg-xdpyinfo
xorg-xkill
xorg-xauth
xorg-xhost
xorg-xset
xorg-xsetroot
xterm

# Wayland
wayland
wayland-utils
xorg-xwayland
weston

# ─────────────────────────────────────────────────────────────
# §07  KDE Plasma – للأجهزة القوية (RAM ≥ 8GB)
# ─────────────────────────────────────────────────────────────
plasma-meta
plasma-desktop
plasma-workspace
plasma-workspace-wallpapers
plasma-nm                    # NetworkManager في KDE
plasma-pa                    # صوت في KDE
plasma-vault                 # تشفير ملفات
plasma-browser-integration
plasma-thunderbolt
plasma-disks                 # مراقبة الأقراص
plasma-firewall               # جدار ناري رسومي
plasma-systemmonitor
plasma-welcome
kde-applications-meta        # كل تطبيقات KDE
kdeconnect                   # ربط الهاتف بالحاسوب
kdegraphics-meta
kdemultimedia-meta
kdenetwork-meta
kdeutils-meta
kdeadmin-meta
kdeaccessibility-meta
kdebase-meta

# KDE Core Apps
dolphin                      # مدير ملفات
konsole                      # محطة طرفية
kate                         # محرر نصوص
kwrite
ark                          # ضاغط/فاضط الملفات
gwenview                     # عارض صور
spectacle                    # لقطة شاشة
okular                       # قارئ PDF
kmail                        # بريد إلكتروني
kscreen                      # إعدادات الشاشة
powerdevil                   # إدارة الطاقة
kmenuedit
kinfocenter
ksystemlog                   # سجلات النظام
kwallet                      # مخزن كلمات المرور
kwallet-pam
kwalletmanager
sddm                         # مدير تسجيل الدخول
sddm-kcm

# KDE Theming
kvantum                      # محرك ثيمات Qt
kvantum-qt5
breeze                       # ثيم KDE الافتراضي
breeze-gtk                   # GTK theme متوافق
breeze-icons
oxygen
oxygen-icons

# ─────────────────────────────────────────────────────────────
# §08  XFCE – للأجهزة المتوسطة (RAM 4-8GB)
# ─────────────────────────────────────────────────────────────
xfce4                        # حزمة XFCE الأساسية
xfce4-goodies                # إضافات XFCE
xfce4-terminal               # محطة طرفية
xfce4-taskmanager            # مدير مهام
xfce4-power-manager          # إدارة طاقة
xfce4-battery-plugin
xfce4-clipman-plugin         # مدير حافظة
xfce4-cpufreq-plugin
xfce4-cpugraph-plugin
xfce4-datetime-plugin
xfce4-diskperf-plugin
xfce4-fsguard-plugin
xfce4-genmon-plugin
xfce4-indicator-plugin
xfce4-mailwatch-plugin
xfce4-mount-plugin
xfce4-netload-plugin
xfce4-notes-plugin           # ملاحظات
xfce4-pulseaudio-plugin
xfce4-screensaver
xfce4-screenshooter          # لقطة شاشة
xfce4-sensors-plugin         # مستشعرات
xfce4-smartbookmark-plugin
xfce4-systemload-plugin
xfce4-timer-plugin
xfce4-weather-plugin         # طقس
xfce4-whiskermenu-plugin     # قائمة تطبيقات Windows-like
xfce4-xkb-plugin             # تغيير لغة لوحة المفاتيح
mousepad                     # محرر نصوص
ristretto                    # عارض صور
parole                       # مشغل وسائط
catfish                      # بحث الملفات
lightdm                      # مدير تسجيل دخول
lightdm-gtk-greeter
lightdm-gtk-greeter-settings

# ─────────────────────────────────────────────────────────────
# §09  LXDE – للأجهزة الضعيفة (RAM < 4GB)
# ─────────────────────────────────────────────────────────────
lxde                         # حزمة LXDE الأساسية
lxde-common
lxappearance                 # مدير مظهر GTK
lxappearance-obconf
lxinput                      # إعدادات الإدخال
lxmenu-data
lxpanel                      # شريط المهام
lxrandr                      # إعدادات الشاشة
lxsession                    # مدير الجلسة
lxshortcut
lxtask                       # مدير مهام
lxterminal                   # محطة طرفية
pcmanfm                      # مدير ملفات خفيف
openbox                      # مدير نوافذ
obconf                       # إعدادات openbox
leafpad                      # محرر نصوص خفيف
gpicview                     # عارض صور خفيف
xarchiver                    # ضاغط ملفات
lxdm                         # مدير تسجيل دخول خفيف

# ─────────────────────────────────────────────────────────────
# §10  ثيم Windows 11  /  Windows 11 Theme
# ─────────────────────────────────────────────────────────────
# AUR packages – تُثبَّت عبر yay/paru
# yay -S windows-11-icon-theme-git
# yay -S fluent-gtk-theme-git
# yay -S bibata-cursor-theme
# yay -S windows-10-dark-icons

# Flatpak Themes (بديل)
# flatpak install org.gtk.Gtk3theme.Windows-11

# مكونات الثيم المفتوحة
tela-icon-theme              # أيقونات مشابهة لـ Win11
numix-circle-icon-theme-git  # أيقونات دائرية
papirus-icon-theme           # أيقونات حديثة
arc-icon-theme
hicolor-icon-theme

# ─────────────────────────────────────────────────────────────
# §11  إدارة الملفات  /  File Management
# ─────────────────────────────────────────────────────────────
thunar                       # XFCE File Manager
thunar-archive-plugin
thunar-media-tags-plugin
thunar-volman
dolphin                      # KDE File Manager
dolphin-plugins
nemo                         # Cinnamon File Manager
nemo-fileroller
nemo-preview
ranger                       # Terminal File Manager
mc                           # Midnight Commander
vifm                         # Vim-like File Manager
pcmanfm                      # PCManFM
nautilus                     # GNOME Files
nnn                          # Terminal File Manager
lf                           # Terminal File Manager

# ─────────────────────────────────────────────────────────────
# §12  متصفحات الإنترنت  /  Web Browsers
# ─────────────────────────────────────────────────────────────
firefox                      # Firefox المعتمد
firefox-i18n-ar              # دعم عربي Firefox
chromium                     # Chromium مفتوح المصدر
google-chrome                # AUR
brave-bin                    # AUR – Brave Browser
microsoft-edge-stable-bin    # AUR – Microsoft Edge
librewolf-bin                # AUR – Firefox خصوصية
tor-browser                  # متصفح Tor للخصوصية

# ─────────────────────────────────────────────────────────────
# §13  البريد والتواصل  /  Email & Communication
# ─────────────────────────────────────────────────────────────
thunderbird                  # بريد إلكتروني (مثل Outlook)
thunderbird-i18n-ar
evolution                    # بريد إلكتروني GNOME
telegram-desktop             # Telegram
discord                      # Discord
signal-desktop               # Signal
element-desktop              # Matrix/Element
slack-desktop                # Slack (AUR)
zoom                         # Zoom (AUR)
skypeforlinux-stable-bin     # Skype (AUR)

# ─────────────────────────────────────────────────────────────
# §14  الإنتاجية والمكتب  /  Productivity & Office
# ─────────────────────────────────────────────────────────────
# Office Suite (بديل Microsoft Office)
libreoffice-fresh            # Writer + Calc + Impress + Draw
libreoffice-fresh-ar         # دعم عربي كامل
libreoffice-fresh-en_US
calligra                     # مجموعة KDE المكتبية

# ملاحظات
obsidian                     # قاعدة معرفة Markdown
joplin-desktop               # مزامنة ملاحظات
cherrytree                   # ملاحظات شجرية
zim                          # ويكي شخصي
xournalpp                    # تدوين PDF + لوح رسم

# قارئ PDF
okular                       # قارئ PDF شامل (KDE)
evince                       # قارئ GNOME
zathura                      # قارئ طرفي
zathura-pdf-poppler
mupdf                        # قارئ خفيف سريع
master-pdf-editor            # محرر PDF كامل (AUR)

# كلمات مرور
keepassxc                    # KeePass لينكس
bitwarden                    # AUR
gnome-keyring
seahorse                     # إدارة المفاتيح

# ─────────────────────────────────────────────────────────────
# §15  الوسائط المتعددة  /  Multimedia
# ─────────────────────────────────────────────────────────────
# مشغل فيديو
vlc                          # أكثر مشغلات فيديو شمولاً
mpv                          # مشغل CLI قوي
smplayer                     # واجهة رسومية لـ mpv/mplayer
celluloid                    # واجهة Gnome لـ mpv
haruna                       # مشغل KDE

# صوت
lollypop                     # مشغل موسيقى مثل Groove
rhythmbox                    # مشغل موسيقى GNOME
amarok                       # مشغل KDE الاحترافي
strawberry                   # مشغل حديث + Spotify-like
cmus                         # مشغل طرفي

# تحرير فيديو / Video Editing
kdenlive                     # محرر فيديو KDE
shotcut                      # محرر فيديو متعدد المنصات
openshot                     # محرر فيديو سهل للمبتدئين
pitivi                       # محرر GNOME
obs-studio                   # OBS للتسجيل والبث

# Codec & Media
ffmpeg                       # codec شامل
gstreamer                    # إطار وسائط
gstreamer-plugin-base
gstreamer-plugin-good
gstreamer-plugin-bad
gstreamer-plugin-ugly
gstreamer-plugin-libav
x264                         # H.264 encoder
x265                         # H.265 encoder
libav-tools
flac                         # FLAC audio
lame                         # MP3 encoder
opus                         # Opus codec
libvorbis
libtheora

# ─────────────────────────────────────────────────────────────
# §16  التصميم والإبداع  /  Design & Creative
# ─────────────────────────────────────────────────────────────
# تحرير صور (بديل Photoshop)
gimp                         # محرر صور شامل
gimp-plugin-registry
krita                        # رسم رقمي احترافي
darktable                    # تعديل RAW
rawtherapee                  # معالجة RAW

# رسومات متجهية (بديل Illustrator)
inkscape                     # رسومات SVG احترافية
karbon                       # رسومات KDE

# تصميم UI (بديل Figma)
penpot                       # بديل Figma مفتوح (Docker)
akira-git                    # AUR

# ثلاثي الأبعاد (بديل 3ds Max / Maya)
blender                      # نمذجة 3D + Animation
freecad                      # CAD مفتوح المصدر
openscad                     # CAD برمجي

# معالجة الصور
imagemagick                  # معالجة دُفعات
graphicsmagick
exiftool                     # بيانات EXIF
optipng                      # ضغط PNG
jpegoptim                    # ضغط JPEG

# خطوط عربية وعالمية
noto-fonts
noto-fonts-arabic            # خطوط عربية شاملة
noto-fonts-cjk               # خطوط آسيوية
noto-fonts-emoji             # Emoji
ttf-ubuntu-font-family
ttf-dejavu
ttf-liberation               # بديل خطوط MS Office
ttf-hack
ttf-cascadia-code            # خط مايكروسوفت
ttf-fira-code
ttf-jetbrains-mono
ttf-roboto
ttf-ms-fonts                 # AUR – خطوط ويندوز الحقيقية
ttf-vista-fonts              # AUR
amiri-font                   # خط أميري العربي
cantarell-fonts

# الطباعة (بديل InDesign)
scribus                      # تخطيط صفحات احترافي
libreoffice-draw

# ─────────────────────────────────────────────────────────────
# §17  الغيمينغ  /  Gaming
# ─────────────────────────────────────────────────────────────
# Steam وتوزيع الألعاب
steam                        # Steam Client
steam-native-runtime
steamtinkerlaunch            # أدوات Steam متقدمة
protontricks                 # Winetricks لـ Steam

# Wine – تشغيل ألعاب ويندوز
wine                         # Wine الكامل
wine-mono
wine-gecko
winetricks                   # تثبيت مكتبات ويندوز
bottles                      # إدارة بيئات Wine رسومياً
lutris                       # مشغل ألعاب شامل
heroic-games-launcher-bin    # AUR – Epic Games + GOG

# Proton
proton-ge-custom-bin         # AUR – Proton-GE محسّن
protonup-qt                  # مدير إصدارات Proton

# DXVK + VKD3D (DirectX → Vulkan)
dxvk-bin                     # AUR – DirectX 9/10/11 → Vulkan
vkd3d                        # DirectX 12 → Vulkan
lib32-vkd3d

# أداء الغيمينغ
gamemode                     # تحسين أداء اللعب
lib32-gamemode
gamescope                    # Valve compositor للألعاب
mangohud                     # HUD للإحصائيات أثناء اللعب
lib32-mangohud
goverlay                     # واجهة رسومية MangoHud

# محاكيات
retroarch                    # محاكي شامل
retroarch-assets-xmb
libretro-core-info
dolphin-emu                  # GameCube / Wii
pcsx2                        # PlayStation 2
rpcs3                        # PlayStation 3
citra                        # Nintendo 3DS
mgba                         # Game Boy Advance
ppsspp                       # PSP
yuzu                         # Nintendo Switch
ryujinx                      # Nintendo Switch بديل

# أدوات تحكم
sc-controller                # Steam Controller
antimicro                    # عصا التحكم → لوحة مفاتيح
jstest-gtk                   # اختبار عصا التحكم
xboxdrv                      # Xbox driver

# ─────────────────────────────────────────────────────────────
# §18  توافق ويندوز 11  /  Windows 11 Compatibility
# ─────────────────────────────────────────────────────────────
# .NET on Linux
dotnet-runtime               # .NET Runtime
dotnet-sdk                   # .NET SDK
mono                         # .NET Framework مفتوح
mono-tools

# مكتبات Wine 32-bit
lib32-libpulse
lib32-alsa-plugins
lib32-gnutls
lib32-libxcomposite
lib32-libxinerama
lib32-mpg123

# بدائل تطبيقات ويندوز 11
# Notepad  →  kate / mousepad / geany
kate
mousepad
geany
# Paint / Paint3D  →  kolourpaint / pinta
kolourpaint
pinta
# Calculator  →  gnome-calculator / kcalc
gnome-calculator
kcalc
speedcrunch
# Clock  →  gnome-clocks
gnome-clocks
# Camera  →  cheese / guvcview
cheese
guvcview
# Photos  →  shotwell / gwenview
shotwell
gwenview
# Maps  →  gnome-maps / marble
gnome-maps
marble
# Weather  →  gnome-weather
gnome-weather
# Sticky Notes  →  xpad / knotes
xpad
knotes
# Sound Recorder  →  gnome-sound-recorder
gnome-sound-recorder
kwave
audacity
# WordPad  →  libreoffice-writer / abiword
abiword
# Screen Snipping  →  flameshot / spectacle
flameshot
spectacle
gnome-screenshot
# Remote Desktop  →  remmina
remmina
remmina-plugin-rdp
remmina-plugin-vnc
freerdp
xrdp
# BitLocker  →  veracrypt
veracrypt
cryptsetup
# Hyper-V  →  virt-manager
virt-manager
qemu-full
libvirt
# Windows Hello  →  fprintd / howdy
fprintd
fprintd-pam
howdy-git                    # AUR – بصمة الوجه
# MS Store  →  pamac / discover / flatpak
pamac-aur                    # AUR
discover
flatpak
# OneDrive  →  rclone
rclone
# PowerShell  →  powershell-bin
powershell-bin               # AUR

# ─────────────────────────────────────────────────────────────
# §19  الأمن السيبراني  /  Cybersecurity (Kali-inspired)
# ─────────────────────────────────────────────────────────────
## مسح الشبكة
nmap                         # مسح المنافذ
masscan                      # مسح سريع
rustscan                     # مسح سريع جداً
netdiscover                  # اكتشاف الشبكة
arp-scan                     # ARP Scan
zenmap                       # واجهة رسومية nmap

## كسر كلمات المرور
john                         # John the Ripper
hashcat                      # GPU Password Cracker
hydra                        # Brute-Force بروتوكولات
medusa
ncrack
ophcrack                     # Windows Passwords

## اختبار WiFi
aircrack-ng                  # WiFi Security Testing
airgeddon-git                # AUR
reaver                       # WPS Cracking
bully                        # WPS Cracking
pixiewps
wifite2                      # AUR – آلي للـ WiFi

## تحليل الشبكة
wireshark-qt                 # تحليل حزم الشبكة
tshark                       # Wireshark CLI
tcpdump
ettercap-gtk                 # MITM
dsniff                       # Network Sniffing
kismet                       # Wireless Monitor

## اختبار ويب
nikto                        # فحص ثغرات الويب
sqlmap                       # SQL Injection
gobuster                     # Directory Bruteforce
ffuf                         # Web Fuzzing
whatweb                      # Web Fingerprint
wafw00f                      # Web Application Firewall Detect

## اختراق الشبكات
metasploit                   # إطار الاختراق الشامل
armitage                     # واجهة Metasploit

## الهندسة العكسية
ghidra                       # NSA Reverse Engineering Tool
radare2                      # RE Framework
cutter                       # واجهة رسومية r2
gdb                          # GNU Debugger
pwndbg                       # GDB plugin

## الطب الشرعي الرقمي
autopsy                      # Digital Forensics GUI
sleuthkit                    # CLI Forensics
volatility3                  # Memory Forensics
testdisk                     # استعادة الأقراص
photorec                     # استعادة الملفات
foremost                     # File Carving

## التخفي والخصوصية
tor                          # Tor Network
proxychains-ng               # توجيه عبر Proxy
i2p                          # I2P Network

## OSINT
recon-ng                     # OSINT Framework
theharvester                 # جمع المعلومات
sherlock                     # بحث عن المستخدم عبر المنصات

## فحص النظام
lynis                        # فحص أمن النظام
chkrootkit                   # فحص Rootkit
rkhunter                     # Rootkit Hunter
tiger                        # أمن النظام

## التشفير
gnupg                        # GPG Encryption
gpgme
hashdeep                     # Hash Files

# ─────────────────────────────────────────────────────────────
# §20  جدار الحماية والأمن  /  Firewall & System Security
# ─────────────────────────────────────────────────────────────
ufw                          # جدار ناري بسيط
gufw                         # واجهة رسومية UFW
firewalld                    # جدار ناري ديناميكي
nftables                     # نظام القواعد الحديث
iptables                     # قواعد شبكة قديمة
ipset
fail2ban                     # حماية من Brute-Force
clamav                       # فيروسات مفتوح المصدر
clamtk                       # واجهة رسومية ClamAV
apparmor                     # تحكم في صلاحيات التطبيقات
apparmor-profiles
selinux-utils                # SELinux
audit                        # نظام التدقيق
aide                         # كشف تغيير الملفات
firejail                     # Sandbox للتطبيقات
bubblewrap                   # عزل التطبيقات
polkit                       # إدارة الصلاحيات

# ─────────────────────────────────────────────────────────────
# §21  إشعارات النظام  /  System Notifications
# ─────────────────────────────────────────────────────────────
dunst                        # خادم إشعارات خفيف
libnotify                    # مكتبة الإشعارات
notification-daemon          # خادم إشعارات GNOME
xfce4-notifyd                # إشعارات XFCE
plasma-workspace             # إشعارات KDE (مدمجة)

# ─────────────────────────────────────────────────────────────
# §22  النسخ الاحتياطي والاستعادة  /  Backup & Restore
# ─────────────────────────────────────────────────────────────
timeshift                    # Snapshot النظام (مثل System Restore)
timeshift-autosnap           # AUR – snapshots تلقائي قبل pacman
backintime                   # نسخ احتياطي بسيط
deja-dup                     # GNOME Backup
duplicati                    # AUR – نسخ مشفرة سحابية
rsync                        # مزامنة ملفات
luckybackup                  # واجهة rsync رسومية
borgbackup                   # نسخ احتياطي متقدم
vorta                        # واجهة BorgBackup
snapper                      # Snapshots لـ Btrfs/LVM
grub-btrfs                   # إضافة snapshots لـ GRUB
snap-pac                     # AUR – snap عند تثبيت pacman
clonezilla                   # استنساخ كامل للقرص

# ─────────────────────────────────────────────────────────────
# §23  التطوير  /  Development Tools
# ─────────────────────────────────────────────────────────────
# Git & Version Control
git
git-lfs
github-cli
gitg
git-cola
meld                         # مقارنة الملفات رسومياً
lazygit                      # Git TUI

# محررات الكود
code                         # VS Code (OSS)
visual-studio-code-bin       # AUR – VS Code الرسمي
sublime-text-4               # AUR
geany                        # محرر خفيف متعدد اللغات
kdevelop                     # IDE KDE
codeblocks                   # IDE C++
intellij-idea-community-edition  # AUR – Java IDE
pycharm-community-edition    # AUR – Python IDE

# لغات
python                       # Python 3
python-pip
python-setuptools
python-virtualenv
python-poetry
nodejs                       # Node.js
npm
yarn
go                           # Golang
rust                         # Rust
ruby                         # Ruby
php                          # PHP
composer
jdk-openjdk                  # Java
jre-openjdk
lua                          # Lua
perl                         # Perl
r                            # R Language

# أدوات بناء
cmake
make
ninja
meson
autoconf
automake
libtool
pkg-config

# قواعد البيانات
mariadb                      # MySQL
postgresql
sqlite
redis
mongodb-bin                  # AUR
dbeaver                      # GUI قواعد بيانات
mysql-workbench

# DevOps
docker
docker-compose
kubectl
terraform
ansible

# ─────────────────────────────────────────────────────────────
# §24  أدوات النظام  /  System Tools
# ─────────────────────────────────────────────────────────────
# مراقبة
htop                         # مدير مهام تفاعلي
btop                         # مدير مهام جميل
glances                      # مراقبة شاملة
conky                        # معلومات على سطح المكتب
mission-center               # مراقبة GNOME حديث
ksysguard                    # مراقبة KDE

# محطة طرفية
bash
zsh
zsh-completions
zsh-autosuggestions
zsh-syntax-highlighting
fish                         # محطة ودودة
tmux                         # مضاعفة الطرفية
screen
nano
vim
neovim
micro                        # محرر بسيط

# أدوات ملفات
tree
ranger
mc
nnn
lf
bat                          # cat ملون
exa                          # ls محسّن
lsd                          # ls مع أيقونات
fzf                          # بحث تفاعلي
ripgrep                      # grep سريع
fd                           # find سريع
zoxide                       # cd ذكي
starship                     # prompt جميل

# ضغط
p7zip
zip
unzip
unrar
arj
lhasa
cabextract

# الطباعة
cups
cups-filters
cups-pdf
ghostscript
gutenprint
system-config-printer
hplip                        # HP Printers

# USB
usbutils
libusb
usb_modeswitch
mtpfs                        # MTP
gvfs-mtp
android-tools
android-udev

# الطاقة
tlp                          # تحسين البطارية
tlp-rdw
powertop                     # تحليل الطاقة
auto-cpufreq                 # AUR – تردد تلقائي

# ─────────────────────────────────────────────────────────────
# §25  دعم اللغة العربية  /  Arabic Language Support
# ─────────────────────────────────────────────────────────────
# Locales
glibc                        # يحتوي locale
ibus                         # إطار إدخال
ibus-m17n                    # دعم عربي
ibus-libpinyin
fcitx5                       # إطار إدخال محسّن
fcitx5-m17n
fcitx5-qt
fcitx5-gtk
m17n-lib                     # مكتبة متعددة اللغات
m17n-db

# الخطوط العربية
noto-fonts-arabic
ttf-amiri                    # AUR – خط أميري كلاسيكي
ttf-scheherazade              # خط شهرزاد
ttf-arabeyes-fonts           # AUR
ttf-qurancomplex-fonts       # AUR – خطوط القرآن

# القاموس العربي
aspell-ar                    # تدقيق إملائي
hunspell-ar                  # قاموس Hunspell
myspell-ar

# ─────────────────────────────────────────────────────────────
# §26  إدارة الحزم  /  Package Management
# ─────────────────────────────────────────────────────────────
pacman
pacman-contrib               # paccache + أدوات
yay                          # AUR Helper
paru                         # AUR Helper محسّن
pkgfile                      # البحث عن ملفات الحزم
flatpak                      # حزم Flatpak
snapd                        # حزم Snap
pamac-aur                    # AUR – واجهة رسومية Pamac
discover                     # KDE Software Center
packagekit-qt5

# ─────────────────────────────────────────────────────────────
# §27  مشغل التطبيقات  /  Application Launchers
# ─────────────────────────────────────────────────────────────
rofi                         # مشغل تطبيقات + بحث
wofi                         # Wayland Launcher
ulauncher                    # مشغل GTK حديث
albert                       # مشغل قوي (Qt)

# ─────────────────────────────────────────────────────────────
# §28  دعم Ventoy والتثبيت  /  Ventoy & Installer
# ─────────────────────────────────────────────────────────────
# Calamares – مثبّت رسومي
calamares                    # مثبّت النظام
# Ventoy Support
ventoy-bin                   # AUR – إنشاء USB متعدد ISO

# ─────────────────────────────────────────────────────────────
# §29  إضافات من مجلد apps/  /  Extra Apps from apps/ folder
# ─────────────────────────────────────────────────────────────
# هذه الحزم تُثبَّت من مجلد apps/ إن وُجد
# يُسرد محتواه لاحقاً بواسطة install_local_apps()

MANIFEST

  ok "تم توليد قائمة الحزم: $MANIFEST_FILE"
  info "عدد الأسطر: $(wc -l < "$MANIFEST_FILE")"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# [9]  إعداد ملفات الإعداد  /  Generate Configuration Files
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
generate_configs() {
  section "توليد ملفات الإعداد"
  mkdir -p "$OUT_DIR/config"/{system,kde,xfce,lxde,calamares,grub,locale,firewall,backup}

  # ─── pacman.conf ─────────────────────────────────────────────
  cat > "$OUT_DIR/config/system/pacman.conf" << 'PACMAN'
[options]
HoldPkg      = pacman glibc
Architecture = auto
Color
ILoveCandy
CheckSpace
VerbosePkgLists
ParallelDownloads = 8
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[multilib]
Include = /etc/pacman.d/mirrorlist

[blackarch]
Server = https://blackarch.org/blackarch/$repo/os/$arch
SigLevel = Never
PACMAN

  # ─── locale.gen ──────────────────────────────────────────────
  cat > "$OUT_DIR/config/locale/locale.gen" << 'LOC'
ar_DZ.UTF-8 UTF-8
ar_EG.UTF-8 UTF-8
ar_MA.UTF-8 UTF-8
ar_SA.UTF-8 UTF-8
en_US.UTF-8 UTF-8
en_GB.UTF-8 UTF-8
fr_FR.UTF-8 UTF-8
LOC

  cat > "$OUT_DIR/config/locale/locale.conf" << 'LCONF'
LANG=en_US.UTF-8
LC_MESSAGES=en_US.UTF-8
LC_ADDRESS=ar_DZ.UTF-8
LC_COLLATE=ar_DZ.UTF-8
LC_MONETARY=ar_DZ.UTF-8
LC_NUMERIC=ar_DZ.UTF-8
LC_TIME=ar_DZ.UTF-8
LCONF

  # ─── vconsole.conf (لوحة المفاتيح) ───────────────────────────
  cat > "$OUT_DIR/config/locale/vconsole.conf" << 'VC'
KEYMAP=us
FONT=ter-u16n
FONT_MAP=8859-6
VC

  # ─── GRUB config ─────────────────────────────────────────────
  cat > "$OUT_DIR/config/grub/grub" << 'GRUB'
GRUB_DEFAULT=0
GRUB_TIMEOUT=10
GRUB_TIMEOUT_STYLE=menu
GRUB_DISTRIBUTOR="Atlas Linux"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3 rd.systemd.show_status=auto rd.udev.log_level=3 vt.global_cursor_default=0 mitigations=off"
GRUB_CMDLINE_LINUX=""
GRUB_PRELOAD_MODULES="part_gpt part_msdos"
GRUB_ENABLE_CRYPTODISK=n
GRUB_SAVEDEFAULT=true
GRUB_DEFAULT=saved
GRUB_DISABLE_RECOVERY=true
GRUB_THEME="/boot/grub/themes/atlas/theme.txt"
GRUB_GFXMODE=1920x1080,1366x768,auto
GRUB_GFXPAYLOAD_LINUX=keep
GRUB_TERMINAL_OUTPUT=gfxterm
GRUB_DISABLE_OS_PROBER=false
GRUB

  # ─── mkinitcpio.conf ─────────────────────────────────────────
  cat > "$OUT_DIR/config/system/mkinitcpio.conf" << 'MKINIT'
MODULES=(btrfs nvme amdgpu i915 nouveau)
BINARIES=()
FILES=()
HOOKS=(base udev autodetect microcode modconf block filesystems keyboard fsck)
COMPRESSION="zstd"
COMPRESSION_OPTIONS=(-2)
MKINIT

  # ─── UFW (جدار الحماية) ──────────────────────────────────────
  cat > "$OUT_DIR/config/firewall/ufw-setup.sh" << 'UFW_SETUP'
#!/bin/bash
# إعداد UFW الأولي لنظام Atlas Linux
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 53
ufw allow 123/udp        # NTP
ufw allow 1714:1764/tcp  # KDE Connect
ufw allow 1714:1764/udp  # KDE Connect
ufw allow in proto udp to any port 5353  # mDNS
ufw --force enable
ufw status verbose
echo "✓ UFW جاهز"
UFW_SETUP
  chmod +x "$OUT_DIR/config/firewall/ufw-setup.sh"

  # ─── Fail2Ban config ─────────────────────────────────────────
  cat > "$OUT_DIR/config/firewall/jail.local" << 'FAIL2BAN'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5
backend  = systemd
action   = %(action_mwl)s

[sshd]
enabled = true
port    = ssh
filter  = sshd
logpath = /var/log/auth.log
maxretry = 3

[recidive]
enabled  = true
logpath  = /var/log/fail2ban.log
banaction = ufw
bantime  = 86400
findtime = 86400
maxretry = 5
FAIL2BAN

  # ─── Timeshift Auto-Backup config ────────────────────────────
  cat > "$OUT_DIR/config/backup/timeshift.json" << 'TS'
{
  "backup_device_uuid": "auto",
  "parent_device_uuid": "",
  "do_first_run": false,
  "btrfs_mode": false,
  "include_btrfs_home_for_backup": false,
  "stop_cron_emails": true,
  "schedule_monthly": false,
  "schedule_weekly": false,
  "schedule_daily": true,
  "schedule_hourly": false,
  "schedule_boot": true,
  "count_monthly": "2",
  "count_weekly": "3",
  "count_daily": "5",
  "count_hourly": "6",
  "count_boot": "5",
  "snapshot_size": "0",
  "snapshot_count": "0",
  "date_format": "%Y-%m-%d %H:%M:%S",
  "exclude": [
    "+ /root/**",
    "+ /home/**",
    "- /var/cache/pacman/pkg/**",
    "- /tmp/**"
  ],
  "exclude-apps": []
}
TS

  # ─── SDDM theme config (ثيم تسجيل دخول) ─────────────────────
  cat > "$OUT_DIR/config/kde/sddm.conf" << 'SDDM'
[Theme]
Current=sugar-candy
CursorTheme=Breeze_Snow
Font=Noto Sans Arabic,10,-1,5,50,0,0,0,0,0

[General]
HaltCommand=/usr/bin/systemctl poweroff
RebootCommand=/usr/bin/systemctl reboot
Numlock=on
InputMethod=qtvirtualkeyboard
SDDM

  # ─── KDE Windows 11 Theme setup script ───────────────────────
  cat > "$OUT_DIR/config/kde/apply-win11-theme.sh" << 'WIN11'
#!/bin/bash
# تطبيق ثيم Windows 11 على KDE Plasma
# يُنفَّذ بعد تسجيل الدخول الأول

# تثبيت الحزم اللازمة من AUR
yay -S --noconfirm \
  windows-11-kde-theme-git \
  tela-circle-icon-theme-git \
  bibata-cursor-theme \
  plasma5-applets-win7-show-desktop \
  plasma5-applets-better-inline-clock \
  latte-dock 2>/dev/null || true

# تطبيق ثيم Windows 11
if command -v plasma-apply-lookandfeel &>/dev/null; then
  plasma-apply-lookandfeel -a org.kde.breezedark.desktop 2>/dev/null || true
fi

# تغيير الأيقونات
if command -v kwriteconfig5 &>/dev/null; then
  kwriteconfig5 --file kdeglobals --group Icons --key Theme "Tela-circle-dark"
  kwriteconfig5 --file kdeglobals --group KDE --key widgetStyle "Breeze"
  kwriteconfig5 --file kcminputrc --group Mouse --key cursorTheme "Bibata-Modern-Ice"
  kwriteconfig5 --file plasmarc --group Theme --key name "breeze-dark"
fi

# تطبيق خلفية Windows 11
if [[ -f /usr/share/wallpapers/atlas/win11-wallpaper.jpg ]]; then
  dbus-send --session --dest=org.kde.plasmashell /PlasmaShell \
    org.kde.PlasmaShell.evaluateScript \
    "string:
var allDesktops = desktops();
for (var i=0; i<allDesktops.length; i++) {
  var d = allDesktops[i];
  d.wallpaperPlugin = 'org.kde.image';
  d.currentConfigGroup = ['Wallpaper', 'org.kde.image', 'General'];
  d.writeConfig('Image', 'file:///usr/share/wallpapers/atlas/win11-wallpaper.jpg');
}" 2>/dev/null || true
fi

echo "✓ تم تطبيق ثيم Windows 11"
WIN11
  chmod +x "$OUT_DIR/config/kde/apply-win11-theme.sh"

  # ─── XFCE Windows 11 Theme ───────────────────────────────────
  cat > "$OUT_DIR/config/xfce/apply-win11-theme.sh" << 'XFCE_WIN11'
#!/bin/bash
# تطبيق ثيم Windows 11 على XFCE

yay -S --noconfirm \
  windows-11-gtk-theme-git \
  tela-circle-icon-theme-git \
  bibata-cursor-theme 2>/dev/null || true

# GTK Theme
xfconf-query -c xsettings -p /Net/ThemeName -s "Windows-11-Dark" 2>/dev/null || true
xfconf-query -c xsettings -p /Net/IconThemeName -s "Tela-circle-dark" 2>/dev/null || true
xfconf-query -c xsettings -p /Gtk/CursorThemeName -s "Bibata-Modern-Ice" 2>/dev/null || true

# XFWM4 Theme
xfconf-query -c xfwm4 -p /general/theme -s "Windows-11-Dark" 2>/dev/null || true
echo "✓ تم تطبيق ثيم Windows 11 على XFCE"
XFCE_WIN11
  chmod +x "$OUT_DIR/config/xfce/apply-win11-theme.sh"

  # ─── إعدادات Calamares (مثبّت النظام) ──────────────────────
  cat > "$OUT_DIR/config/calamares/settings.conf" << 'CALA'
---
modules-search: [ local ]
sequence:
  - show:
    - welcome
    - locale
    - keyboard
    - partition
    - users
    - summary
  - exec:
    - partition
    - mount
    - unpackfs
    - machineid
    - fstab
    - locale
    - keyboard
    - localecfg
    - users
    - networkcfg
    - hwclock
    - services-systemd
    - displaymanager
    - grubcfg
    - bootloader
    - packages
    - removeuser
    - luksbootkeyfile
    - plymouthcfg
    - initcpiocfg
    - initcpio
    - postcfg
    - umount
  - show:
    - finished
branding: atlas
prompt-install: false
dont-chroot: false
oem-setup: false
disable-cancel: false
disable-cancel-during-exec: false
CALA

  cat > "$OUT_DIR/config/calamares/branding.desc" << 'BRAND'
---
componentName: atlas
welcomeStyleCalamares: false
welcomeExpandingLogo: true
strings:
  productName: "Atlas Linux"
  shortProductName: "Atlas"
  version: "1.0.0"
  shortVersion: "1.0"
  versionedName: "Atlas Linux 1.0"
  shortVersionedName: "Atlas 1.0"
  bootloaderEntryName: "Atlas Linux"
  productUrl: "https://atlas-linux.org"
  supportUrl: "https://atlas-linux.org/support"
  knownIssuesUrl: "https://atlas-linux.org/issues"
  releaseNotesUrl: "https://atlas-linux.org/release-notes"
images:
  productLogo: "atlas-logo.png"
  productIcon: "atlas-icon.png"
  productWelcome: "atlas-welcome.png"
BRAND

  ok "ملفات الإعداد جاهزة في: $OUT_DIR/config/"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# [10]  إعداد archiso profile  /  Setup archiso Profile
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
setup_archiso_profile() {
  section "إعداد ملف archiso"

  if ! $IS_ARCH; then
    warn "تخطي إعداد archiso (بيئة غير Arch)"
    return 0
  fi

  if [[ ! -d /usr/share/archiso/configs/releng ]]; then
    auto_fix archiso_missing
    [[ ! -d /usr/share/archiso/configs/releng ]] && { warn "archiso غير متاح"; return 0; }
  fi

  cp -rf /usr/share/archiso/configs/releng/* "$BUILD_DIR/"
  mkdir -p "$BUILD_DIR/airootfs/etc/atlas"
  mkdir -p "$BUILD_DIR/airootfs/usr/local/bin"
  mkdir -p "$BUILD_DIR/airootfs/etc/skel/.config"

  # نسخ ملفات الإعداد
  [[ -d "$OUT_DIR/config" ]] && cp -r "$OUT_DIR/config"/* "$BUILD_DIR/airootfs/etc/" 2>/dev/null || true

  # profiledef.sh
  cat > "$BUILD_DIR/profiledef.sh" << 'PROFILE'
#!/usr/bin/env bash
iso_name="atlas-linux"
iso_label="ATLAS_$(date +%Y%m)"
iso_publisher="Atlas Linux Team"
iso_application="Atlas Linux Live/Install"
iso_version="1.0.0"
install_dir="arch"
buildmodes=('iso')
bootmodes=('bios.syslinux.mbr' 'bios.syslinux.eltorito' 'uefi-ia32.grub.esp' 'uefi-x64.grub.esp' 'uefi-x64.grub.eltorito')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '15' '-b' '1M' '-no-progress')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/usr/local/bin/atlas-first-boot.sh"]="0:0:755"
  ["/usr/local/bin/atlas-install-check.sh"]="0:0:755"
)
PROFILE

  # packages.x86_64 – استخراج أسماء الحزم من MANIFEST
  grep -E '^[a-zA-Z]' "$MANIFEST_FILE" | awk '{print $1}' | sort -u > "$BUILD_DIR/packages.x86_64"
  echo "calamares" >> "$BUILD_DIR/packages.x86_64"

  ok "archiso profile جاهز"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# [11]  توليد سكريبتات الإعداد الداخلية  /  Generate Airootfs Scripts
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
generate_airootfs_scripts() {
  section "توليد سكريبتات الإعداد الداخلية"

  if ! $IS_ARCH; then
    warn "تخطي (بيئة غير Arch)"
    # نحفظها في OUT_DIR بدلاً
    local SCRIPTS_DIR="$OUT_DIR/airootfs-scripts"
    mkdir -p "$SCRIPTS_DIR"
    _write_airootfs_scripts "$SCRIPTS_DIR"
    return 0
  fi

  mkdir -p "$BUILD_DIR/airootfs/usr/local/bin"
  _write_airootfs_scripts "$BUILD_DIR/airootfs/usr/local/bin"
}

_write_airootfs_scripts() {
  local DIR="$1"

  # ─── customize_airootfs.sh ────────────────────────────────────
  cat > "$DIR/customize_airootfs.sh" << 'CUSTOM'
#!/usr/bin/env bash
# يُنفَّذ داخل chroot أثناء بناء الـ ISO

set -e

echo "=== Atlas Linux: customize_airootfs.sh ==="

# locale
sed -i 's/^#ar_DZ/ar_DZ/; s/^#ar_EG/ar_EG/; s/^#en_US/en_US/; s/^#fr_FR/fr_FR/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# timezone
ln -sf /usr/share/zoneinfo/Africa/Algiers /etc/localtime 2>/dev/null || \
ln -sf /usr/share/zoneinfo/Africa/Cairo   /etc/localtime 2>/dev/null || true

# لوحة المفاتيح
cat > /etc/vconsole.conf << 'VC'
KEYMAP=us
FONT=ter-u16n
VC

# hostname
echo "atlas" > /etc/hostname
cat > /etc/hosts << 'HOSTS'
127.0.0.1   localhost
::1         localhost
127.0.1.1   atlas.localdomain atlas
HOSTS

# تفعيل الخدمات
systemctl enable NetworkManager
systemctl enable sshd
systemctl enable cups
systemctl enable bluetooth
systemctl enable avahi-daemon
systemctl enable tlp
systemctl enable thermald
systemctl enable ufw
systemctl enable fail2ban
systemctl enable timeshift-autosnap
systemctl enable libvirtd
systemctl enable docker
systemctl enable apparmor
systemctl enable firewalld

# مستخدم live
useradd -m -G wheel,audio,video,network,storage,input,docker,libvirt \
  -s /bin/zsh -c "Atlas User" atlasuser 2>/dev/null || true
echo "atlasuser:atlas" | chpasswd
echo "root:atlas" | chpasswd
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/atlas

# إعداد ZSH كشل افتراضي مع Oh-My-Zsh
if command -v zsh &>/dev/null; then
  chsh -s /usr/bin/zsh atlasuser 2>/dev/null || true
  chsh -s /usr/bin/zsh root 2>/dev/null || true
fi

# تثبيت AUR helper (paru)
if ! command -v paru &>/dev/null; then
  sudo -u atlasuser bash -c '
    cd /tmp
    git clone https://aur.archlinux.org/paru-bin.git
    cd paru-bin
    makepkg -si --noconfirm
  ' 2>/dev/null || true
fi

# تثبيت yay
if ! command -v yay &>/dev/null; then
  sudo -u atlasuser bash -c '
    cd /tmp
    git clone https://aur.archlinux.org/yay-bin.git
    cd yay-bin
    makepkg -si --noconfirm
  ' 2>/dev/null || true
fi

# AUR packages
AUR_PKGS=(
  windows-11-kde-theme-git
  tela-circle-icon-theme-git
  bibata-cursor-theme
  ttf-ms-fonts
  ttf-amiri
  google-chrome
  brave-bin
  microsoft-edge-stable-bin
  librewolf-bin
  visual-studio-code-bin
  paru-bin
  yay-bin
  proton-ge-custom-bin
  protonup-qt
  dxvk-bin
  mangohud
  lib32-mangohud
  gamemode
  lib32-gamemode
  heroic-games-launcher-bin
  pamac-aur
  timeshift
  timeshift-autosnap
  snap-pac
  bottles
  ventoy-bin
  powershell-bin
  howdy-git
  rustscan
  wifite2
  airgeddon-git
  recon-ng
  master-pdf-editor
  grub-customizer
)

for pkg in "${AUR_PKGS[@]}"; do
  sudo -u atlasuser paru -S --noconfirm --skipreview "$pkg" 2>/dev/null || \
  sudo -u atlasuser yay -S --noconfirm --answerdiff=None "$pkg" 2>/dev/null || \
  echo "تخطي: $pkg"
done

# تطبيق إعدادات الأمان
bash /usr/local/bin/atlas-security-setup.sh 2>/dev/null || true

# إعداد الخدمات وفق أول تشغيل
cat > /etc/systemd/system/atlas-first-boot.service << 'SVC'
[Unit]
Description=Atlas Linux First Boot Setup
After=network.target
ConditionPathExists=!/etc/atlas/first-boot-done

[Service]
Type=oneshot
ExecStart=/usr/local/bin/atlas-first-boot.sh
ExecStartPost=/bin/touch /etc/atlas/first-boot-done
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SVC
systemctl enable atlas-first-boot.service

echo "=== customize_airootfs.sh اكتمل ==="
CUSTOM
  chmod +x "$DIR/customize_airootfs.sh"

  # ─── atlas-security-setup.sh ─────────────────────────────────
  cat > "$DIR/atlas-security-setup.sh" << 'SEC'
#!/usr/bin/env bash
# إعداد الأمان الشامل لنظام Atlas Linux

# UFW
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80,443/tcp
ufw allow 1714:1764/tcp comment 'KDE Connect'
ufw allow 1714:1764/udp comment 'KDE Connect'
ufw --force enable

# Fail2Ban
systemctl enable fail2ban --now 2>/dev/null || true

# AppArmor
systemctl enable apparmor --now 2>/dev/null || true

# ClamAV - تحديث قاعدة البيانات
if command -v freshclam &>/dev/null; then
  freshclam 2>/dev/null || true
  systemctl enable clamav-freshclam --now 2>/dev/null || true
fi

# تعزيز sysctl
cat >> /etc/sysctl.d/99-atlas-security.conf << 'SYSCTL'
# حماية من الهجمات
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
SYSCTL
sysctl --system 2>/dev/null || true

echo "✓ إعدادات الأمان مكتملة"
SEC
  chmod +x "$DIR/atlas-security-setup.sh"

  # ─── atlas-backup-setup.sh ────────────────────────────────────
  cat > "$DIR/atlas-backup-setup.sh" << 'BAK'
#!/usr/bin/env bash
# إعداد نسخ احتياطية تلقائية

# Timeshift - نسخ احتياطي يومي
if command -v timeshift &>/dev/null; then
  timeshift --create --comments "Atlas First Backup" --tags D 2>/dev/null || true
fi

# snapper إذا كان Btrfs
if command -v snapper &>/dev/null && mount | grep -q "btrfs"; then
  snapper -c root create-config / 2>/dev/null || true
  snapper -c home create-config /home 2>/dev/null || true
  systemctl enable snapper-timeline.timer --now 2>/dev/null || true
  systemctl enable snapper-cleanup.timer --now 2>/dev/null || true
fi

# cron للنسخ الاحتياطية
cat > /etc/cron.d/atlas-backup << 'CRON'
# نسخة احتياطية يومية
0 2 * * * root /usr/bin/timeshift --create --comments "Auto Daily" --tags D >/dev/null 2>&1
# تنظيف أسبوعي
0 3 * * 0 root /usr/bin/timeshift --delete --scripted >/dev/null 2>&1
CRON

echo "✓ إعدادات النسخ الاحتياطي مكتملة"
BAK
  chmod +x "$DIR/atlas-backup-setup.sh"

  # ─── atlas-install-check.sh ───────────────────────────────────
  cat > "$DIR/atlas-install-check.sh" << 'CHKINSTALL'
#!/usr/bin/env bash
# فحص وتنظيف ما بعد التثبيت

echo "=== Atlas Linux Post-Install Check ==="

# تفعيل الخدمات الأساسية
SERVICES=(
  NetworkManager bluetooth cups avahi-daemon
  ufw fail2ban clamav-freshclam apparmor
  tlp thermald docker libvirtd
  atlas-first-boot
)
for svc in "${SERVICES[@]}"; do
  systemctl enable "$svc" --now 2>/dev/null && echo "✓ $svc" || echo "⚠ $svc (تخطي)"
done

# تحديث الـ initramfs
mkinitcpio -P 2>/dev/null || true

# تحديث GRUB
grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || true

# locale
locale-gen 2>/dev/null || true

# تحديث cache الأيقونات
update-desktop-database 2>/dev/null || true
gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true
gtk-update-icon-cache -f /usr/share/icons/Papirus 2>/dev/null || true

echo "=== الفحص اكتمل ==="
CHKINSTALL
  chmod +x "$DIR/atlas-install-check.sh"

  ok "سكريبتات airootfs جاهزة في: $DIR"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# [12]  إعداد Calamares (مثبّت النظام)  /  Calamares Installer Setup
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
generate_calamares_config() {
  section "إعداد Calamares – مثبّت النظام الرسومي"

  local CALA_DIR="$OUT_DIR/calamares"
  mkdir -p "$CALA_DIR/modules"

  # modules/partition.conf
  cat > "$CALA_DIR/modules/partition.conf" << 'PART'
---
efi:
  recommendedSize: 512MiB
  minimumSize: 32MiB
defaultFileSystemType: "btrfs"
availableFileSystemTypes: ["btrfs","ext4","xfs","f2fs"]
PART

  # modules/locale.conf
  cat > "$CALA_DIR/modules/locale.conf" << 'LOC2'
---
region: "Africa"
zone: "Algiers"
recommend:
  - "Africa/Algiers"
  - "Africa/Cairo"
  - "Africa/Casablanca"
  - "Asia/Riyadh"
  - "Europe/Paris"
  - "America/New_York"
LOC2

  # modules/users.conf
  cat > "$CALA_DIR/modules/users.conf" << 'USERS'
---
defaultGroups:
  - name: wheel
    must_exist: true
    state: true
  - name: audio
    must_exist: false
    state: true
  - name: video
    must_exist: false
    state: true
  - name: input
    must_exist: false
    state: true
  - name: network
    must_exist: false
    state: true
  - name: storage
    must_exist: false
    state: true
  - name: docker
    must_exist: false
    state: true
  - name: libvirt
    must_exist: false
    state: true
setRootPassword: true
sudoersGroup: "wheel"
doAutoLogin: false
autoLoginGroup: "autologin"
USERS

  # modules/displaymanager.conf
  cat > "$CALA_DIR/modules/displaymanager.conf" << 'DM'
---
displaymanagers:
  - sddm
  - lightdm
  - lxdm
  - gdm
defaultDesktopEnvironment:
  executable: ""
  desktopFile: ""
basicSetup: false
DM

  # modules/packages.conf
  cat > "$CALA_DIR/modules/packages.conf" << 'PKGCONF'
---
backend: pacman
update_db: true
operations:
  - install:
    - yay-bin
    - paru-bin
    - pamac-aur
  - remove:
    - calamares
    - squashfs-tools
PKGCONF

  # modules/postcfg.conf
  cat > "$CALA_DIR/modules/postcfg.conf" << 'POST'
---
scriptpaths:
  - "/usr/local/bin/atlas-install-check.sh"
  - "/usr/local/bin/atlas-first-boot.sh"
  - "/usr/local/bin/atlas-security-setup.sh"
  - "/usr/local/bin/atlas-backup-setup.sh"
POST

  ok "إعدادات Calamares جاهزة: $CALA_DIR"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# [13]  إعداد Ventoy  /  Ventoy Support Configuration
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
generate_ventoy_config() {
  section "إعداد دعم Ventoy"

  local VENTOY_DIR="$OUT_DIR/ventoy"
  mkdir -p "$VENTOY_DIR"

  # ventoy.json – تخصيص قائمة الإقلاع
  cat > "$VENTOY_DIR/ventoy.json" << 'VJSON'
{
  "control": [
    {
      "VTOY_DEFAULT_SEARCH_ROOT": "/atlas"
    },
    {
      "VTOY_LINUX_REMOUNT": "1"
    }
  ],
  "theme": {
    "display_mode": "GUI",
    "ventoy_left": "5%",
    "ventoy_top": "95%",
    "ventoy_color": "#2196f3"
  },
  "injection": [
    {
      "image": "/atlas-linux-1.0.0-x86_64.iso",
      "inject": "/atlas-injection"
    }
  ],
  "auto_install": [
    {
      "image": "/atlas-linux-1.0.0-x86_64.iso",
      "template": "/ventoy/calamares-auto.yaml"
    }
  ],
  "conf_replace": [
    {
      "image": "/atlas-linux-1.0.0-x86_64.iso",
      "org": "/boot/grub/grub.cfg",
      "new": "/ventoy/atlas-grub.cfg"
    }
  ]
}
VJSON

  # GRUB menu entry for Ventoy
  cat > "$VENTOY_DIR/atlas-grub.cfg" << 'VGRUB'
set default=0
set timeout=10
set gfxmode=1920x1080,auto
loadfont unicode

menuentry "Atlas Linux – Live Session" {
  set isofile="/atlas-linux-1.0.0-x86_64.iso"
  loopback loop $isofile
  linux (loop)/arch/boot/x86_64/vmlinuz-linux-zen \
    img_dev=/dev/disk/by-label/Ventoy \
    img_loop=$isofile \
    earlymodules=loop \
    driver=free \
    quiet splash loglevel=3 \
    BOOT_IMAGE=$isofile \
    archisobasedir=arch \
    lang=ar_DZ \
    locale=en_US.UTF-8
  initrd (loop)/arch/boot/x86_64/initramfs-linux-zen.img
}

menuentry "Atlas Linux – Install to Disk" {
  set isofile="/atlas-linux-1.0.0-x86_64.iso"
  loopback loop $isofile
  linux (loop)/arch/boot/x86_64/vmlinuz-linux-zen \
    img_dev=/dev/disk/by-label/Ventoy \
    img_loop=$isofile \
    earlymodules=loop \
    driver=free \
    quiet splash atlas_install=1 \
    BOOT_IMAGE=$isofile \
    archisobasedir=arch
  initrd (loop)/arch/boot/x86_64/initramfs-linux-zen.img
}

menuentry "Atlas Linux – Fallback (LTS Kernel)" {
  set isofile="/atlas-linux-1.0.0-x86_64.iso"
  loopback loop $isofile
  linux (loop)/arch/boot/x86_64/vmlinuz-linux-lts \
    img_dev=/dev/disk/by-label/Ventoy \
    img_loop=$isofile \
    earlymodules=loop \
    driver=free \
    nomodeset \
    BOOT_IMAGE=$isofile \
    archisobasedir=arch
  initrd (loop)/arch/boot/x86_64/initramfs-linux-lts.img
}
VGRUB

  # سكريبت نسخ على USB مع Ventoy
  cat > "$VENTOY_DIR/flash-to-usb.sh" << 'FLASH'
#!/usr/bin/env bash
# نسخ Atlas Linux على USB بطريقة Ventoy
set -e

ISO="${1:-}"
USB="${2:-}"

if [[ -z "$ISO" || -z "$USB" ]]; then
  echo "الاستخدام: $0 atlas-linux-1.0.0-x86_64.iso /dev/sdX"
  echo ""
  echo "الأجهزة المتاحة:"
  lsblk -d -o NAME,SIZE,MODEL | grep -v loop
  exit 1
fi

if [[ ! -f "$ISO" ]]; then
  echo "خطأ: الملف $ISO غير موجود"
  exit 1
fi

echo "⚠ تحذير: سيُحذف كل ما على $USB"
read -rp "هل تريد المتابعة؟ (اكتب 'نعم'): " CONFIRM
[[ "$CONFIRM" != "نعم" ]] && { echo "إلغاء."; exit 0; }

echo "طريقة 1: Ventoy (متعدد ISO)"
if command -v ventoy &>/dev/null; then
  ventoy -i -g "$USB"
  mount "${USB}1" /mnt/ventoy 2>/dev/null || mount "${USB}p1" /mnt/ventoy
  cp "$ISO" /mnt/ventoy/
  cp ventoy.json /mnt/ventoy/ventoy/ 2>/dev/null || true
  umount /mnt/ventoy
  echo "✓ نُسخ على USB عبر Ventoy"
else
  echo "طريقة 2: dd مباشر"
  dd if="$ISO" of="$USB" bs=4M status=progress oflag=sync conv=fsync
  echo "✓ نُسخ على USB عبر dd"
fi
FLASH
  chmod +x "$VENTOY_DIR/flash-to-usb.sh"

  ok "ملفات Ventoy جاهزة: $VENTOY_DIR"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# [14]  تثبيت تطبيقات مجلد apps/  /  Install Local Apps
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
install_local_apps() {
  section "تثبيت تطبيقات مجلد apps/"

  if [[ ! -d "$APPS_DIR" ]] || [[ -z "$(ls -A "$APPS_DIR" 2>/dev/null)" ]]; then
    info "مجلد apps/ فارغ أو غير موجود – تخطي"
    return 0
  fi

  info "محتوى مجلد apps/:"
  ls -la "$APPS_DIR" | tee -a "$LOG_FILE"

  # تثبيت .pkg.tar.zst (حزم Arch)
  find "$APPS_DIR" -name "*.pkg.tar.zst" | while read -r pkg; do
    log "تثبيت حزمة Arch: $(basename "$pkg")"
    if $IS_ROOT && $IS_ARCH; then
      pacman -U --noconfirm "$pkg" 2>/dev/null || warn "فشل تثبيت: $pkg"
    else
      cp "$pkg" "$OUT_DIR/" 2>/dev/null || true
    fi
  done

  # تثبيت .deb (Ubuntu/Codespaces)
  find "$APPS_DIR" -name "*.deb" | while read -r pkg; do
    log "تثبيت حزمة Debian: $(basename "$pkg")"
    if $IS_ROOT && ($IS_UBUNTU || $IS_CODESPACES); then
      dpkg -i "$pkg" 2>/dev/null || apt-get install -f -y 2>/dev/null || warn "فشل: $pkg"
    fi
  done

  # تثبيت .AppImage
  find "$APPS_DIR" -name "*.AppImage" | while read -r app; do
    log "نسخ AppImage: $(basename "$app")"
    cp "$app" "$OUT_DIR/" 2>/dev/null || true
    chmod +x "$OUT_DIR/$(basename "$app")" 2>/dev/null || true
  done

  # تثبيت .flatpak
  find "$APPS_DIR" -name "*.flatpak" | while read -r fp; do
    log "تثبيت Flatpak: $(basename "$fp")"
    flatpak install --noninteractive "$fp" 2>/dev/null || warn "فشل Flatpak: $fp"
  done

  # قراءة apps-list.txt إن وُجد
  if [[ -f "$APPS_DIR/apps-list.txt" ]]; then
    log "قراءة apps-list.txt..."
    while IFS= read -r line; do
      [[ "$line" =~ ^#|^$ ]] && continue
      if $IS_ARCH && $IS_ROOT; then
        pacman -S --noconfirm "$line" 2>/dev/null || \
        yay -S --noconfirm "$line" 2>/dev/null || \
        warn "فشل تثبيت من apps-list: $line"
      fi
    done < "$APPS_DIR/apps-list.txt"
  fi

  ok "تثبيت مجلد apps/ اكتمل"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# [15]  بناء ISO  /  Build ISO
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
build_iso() {
  section "بناء صورة Atlas Linux ISO"

  if ! $IS_ARCH || ! $IS_ROOT; then
    warn "بناء ISO يتطلب Arch Linux + صلاحيات root"
    warn "في GitHub Codespaces، يُنتج هذا السكريبت:"
    warn "  - قائمة الحزم الكاملة"
    warn "  - ملفات الإعداد"
    warn "  - سكريبتات الإعداد الداخلية"
    warn "  - إعدادات Calamares و Ventoy"
    info "لبناء ISO فعلي: شغّل على Arch Linux بصلاحيات root"
    return 0
  fi

  log "جارٍ بناء Atlas Linux ISO..."
  log "هذا قد يستغرق 30-90 دقيقة..."

  # التحقق من المساحة
  FREE_GB=$(( $(df "$BUILD_DIR" | awk 'NR==2{print $4}') / 1024 / 1024 ))
  if (( FREE_GB < 20 )); then
    auto_fix space
    FREE_GB=$(( $(df "$BUILD_DIR" | awk 'NR==2{print $4}') / 1024 / 1024 ))
    (( FREE_GB < 20 )) && { warn "مساحة منخفضة ($FREE_GB GB) – المتابعة على مسؤوليتك"; }
  fi

  mkarchiso \
    -v \
    -w "$BUILD_DIR/work" \
    -o "$OUT_DIR" \
    "$BUILD_DIR" \
    2>&1 | tee -a "$LOG_FILE" || {
    warn "فشل mkarchiso – محاولة إصلاح..."
    pacman -Sy archiso --noconfirm 2>/dev/null || true
    mkarchiso -v -w "$BUILD_DIR/work" -o "$OUT_DIR" "$BUILD_DIR" 2>&1 | tee -a "$LOG_FILE"
  }

  local ISO_FILE
  ISO_FILE=$(find "$OUT_DIR" -name "*.iso" -newer "$LOG_FILE" 2>/dev/null | head -1)
  if [[ -n "$ISO_FILE" ]]; then
    ISO_SIZE=$(du -sh "$ISO_FILE" | cut -f1)
    ok "✓ Atlas Linux ISO جاهز!"
    ok "الملف: $ISO_FILE"
    ok "الحجم: $ISO_SIZE"
    # توليد checksum
    sha256sum "$ISO_FILE" > "${ISO_FILE}.sha256"
    ok "SHA256: ${ISO_FILE}.sha256"
  else
    err "لم يُنتج ملف ISO"
  fi
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# [16]  توليد ملخص HTML  /  Generate HTML Summary Report
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
generate_report() {
  section "توليد تقرير البناء"

  local PKG_COUNT
  PKG_COUNT=$(grep -cE '^[a-zA-Z]' "$MANIFEST_FILE" 2>/dev/null || echo "0")

  cat > "$OUT_DIR/atlas-build-report.html" << HTMLREPORT
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Atlas Linux – تقرير البناء</title>
<style>
  :root { --blue:#1a73e8; --dark:#0d1117; --card:#161b22; --text:#e6edf3; --green:#2ea043; --yellow:#d29922; }
  * { box-sizing:border-box; margin:0; padding:0; }
  body { background:var(--dark); color:var(--text); font-family:'Segoe UI',Tahoma,Arial,sans-serif; padding:2rem; direction:rtl; }
  h1 { color:var(--blue); font-size:2rem; text-align:center; padding:1rem; }
  h2 { color:var(--blue); font-size:1.3rem; border-bottom:1px solid #30363d; padding-bottom:.5rem; margin:1.5rem 0 1rem; }
  .grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(280px,1fr)); gap:1rem; margin:1rem 0; }
  .card { background:var(--card); border:1px solid #30363d; border-radius:12px; padding:1.2rem; }
  .card h3 { color:var(--green); margin-bottom:.5rem; font-size:1rem; }
  .badge { display:inline-block; padding:.2rem .7rem; border-radius:20px; font-size:.8rem; margin:.2rem; }
  .b-green { background:#0d2818; color:var(--green); border:1px solid var(--green); }
  .b-blue  { background:#0c1e35; color:var(--blue);  border:1px solid var(--blue); }
  .b-yellow{ background:#2d2208; color:var(--yellow);border:1px solid var(--yellow); }
  .stat { font-size:2rem; font-weight:bold; color:var(--blue); }
  table { width:100%; border-collapse:collapse; font-size:.85rem; }
  th { background:#21262d; padding:.5rem; text-align:right; }
  td { padding:.4rem .5rem; border-bottom:1px solid #21262d; }
  .logo { text-align:center; font-size:3rem; }
  footer { text-align:center; margin-top:2rem; color:#8b949e; font-size:.8rem; }
</style>
</head>
<body>
<div class="logo">🐧</div>
<h1>Atlas Linux v${ATLAS_VERSION}</h1>
<p style="text-align:center; color:#8b949e;">نظام تشغيل مستقل النواة – Gaming · Design · Office · Security</p>

<div class="grid">
  <div class="card">
    <h3>📊 إحصائيات البناء</h3>
    <div class="stat">${PKG_COUNT}</div>
    <p>حزمة مُعرَّفة</p>
    <br>
    <span class="badge b-blue">v${ATLAS_VERSION}</span>
    <span class="badge b-green">Arch Base</span>
    <span class="badge b-yellow">x86_64</span>
  </div>
  <div class="card">
    <h3>🖥 بيئات سطح المكتب</h3>
    <span class="badge b-blue">KDE Plasma ≥ 8GB RAM</span><br>
    <span class="badge b-green">XFCE 4-8GB RAM</span><br>
    <span class="badge b-yellow">LXDE &lt; 4GB RAM</span>
    <p style="margin-top:.5rem; font-size:.85rem">تُختار تلقائياً عند أول تشغيل</p>
  </div>
  <div class="card">
    <h3>🌍 اللغات</h3>
    <span class="badge b-green">العربية</span>
    <span class="badge b-blue">الإنجليزية</span>
    <span class="badge b-yellow">الفرنسية</span>
    <p style="margin-top:.5rem; font-size:.85rem">تبديل بـ Alt+Shift</p>
  </div>
  <div class="card">
    <h3>🔒 الأمن</h3>
    <span class="badge b-green">UFW Firewall</span>
    <span class="badge b-green">Fail2Ban</span>
    <span class="badge b-green">AppArmor</span>
    <span class="badge b-green">ClamAV</span>
    <span class="badge b-blue">Kali Tools</span>
  </div>
</div>

<h2>📦 فئات الحزم</h2>
<div class="grid">
  <div class="card">
    <h3>🎮 الغيمينغ</h3>
    Steam · Lutris · Wine · Bottles · DXVK · GameMode · MangoHud · Proton-GE · محاكيات
  </div>
  <div class="card">
    <h3>🎨 التصميم</h3>
    GIMP · Krita · Inkscape · Blender · DaVinci · Darktable · Scribus · خطوط عربية
  </div>
  <div class="card">
    <h3>💼 المكتب</h3>
    LibreOffice (عربي) · Thunderbird · Firefox · Obsidian · KeePassXC · Telegram
  </div>
  <div class="card">
    <h3>🔐 الأمن السيبراني</h3>
    Nmap · Metasploit · Wireshark · Ghidra · Aircrack · John · Hydra · Forensics
  </div>
  <div class="card">
    <h3>🪟 توافق ويندوز</h3>
    Wine · Bottles · .NET · بدائل تطبيقات Win11 · ثيم Windows 11
  </div>
  <div class="card">
    <h3>💾 النسخ الاحتياطي</h3>
    Timeshift · BorgBackup · Snapper · Btrfs Snapshots · Déjà Dup
  </div>
</div>

<h2>📁 الملفات المُنتجة</h2>
<table>
  <tr><th>الملف</th><th>الوصف</th></tr>
  <tr><td>atlas-packages.manifest</td><td>قائمة كاملة بكل الحزم</td></tr>
  <tr><td>atlas-first-boot.sh</td><td>اختيار الواجهة تلقائياً حسب الجهاز</td></tr>
  <tr><td>calamares/</td><td>إعدادات مثبّت النظام الرسومي</td></tr>
  <tr><td>ventoy/</td><td>إعدادات Ventoy + سكريبت حرق USB</td></tr>
  <tr><td>config/firewall/</td><td>إعدادات UFW + Fail2Ban</td></tr>
  <tr><td>config/backup/</td><td>إعدادات Timeshift التلقائية</td></tr>
  <tr><td>airootfs-scripts/</td><td>سكريبتات إعداد داخل chroot</td></tr>
  <tr><td>atlas-build-report.html</td><td>هذا التقرير</td></tr>
</table>

<h2>🚀 طريقة الاستخدام</h2>
<div class="card">
  <h3>في GitHub Codespaces</h3>
  <pre style="background:#0d1117; padding:1rem; border-radius:8px; font-size:.85rem; direction:ltr; text-align:left">
bash atlas-linux-build.sh --mode manifest
# يُنتج: قوائم حزم + ملفات إعداد + سكريبتات</pre>
</div>
<br>
<div class="card">
  <h3>بناء ISO كامل (Arch Linux + root)</h3>
  <pre style="background:#0d1117; padding:1rem; border-radius:8px; font-size:.85rem; direction:ltr; text-align:left">
sudo bash atlas-linux-build.sh --mode iso</pre>
</div>
<br>
<div class="card">
  <h3>نسخ على USB عبر Ventoy</h3>
  <pre style="background:#0d1117; padding:1rem; border-radius:8px; font-size:.85rem; direction:ltr; text-align:left">
bash ventoy/flash-to-usb.sh atlas-linux-1.0.0-x86_64.iso /dev/sdX</pre>
</div>

<footer>
  Atlas Linux v${ATLAS_VERSION} "${ATLAS_CODENAME}" · بُني بتاريخ ${ATLAS_DATE} ·
  <a href="#" style="color:var(--blue)">atlas-linux.org</a>
</footer>
</body>
</html>
HTMLREPORT

  ok "التقرير: $OUT_DIR/atlas-build-report.html"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# [17]  ملخص الأخطاء  /  Error Summary
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
print_error_summary() {
  if [[ ${#ERRORS_LOG[@]} -gt 0 ]]; then
    echo ""
    warn "══ ملخص التحذيرات ══"
    for e in "${ERRORS_LOG[@]}"; do
      warn "  - $e"
    done
    warn "هذه أخطاء غير حرجة – لم توقف البناء"
  else
    ok "لا توجد أخطاء!"
  fi
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# [18]  ملخص المخرجات  /  Output Summary
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
print_summary() {
  section "✅ Atlas Linux Build Complete"
  echo -e "${G}"
  echo "  ┌─────────────────────────────────────────────────────┐"
  echo "  │            Atlas Linux v${ATLAS_VERSION} – جاهز             │"
  echo "  ├─────────────────────────────────────────────────────┤"
  echo "  │  📁 مجلد المخرجات: $OUT_DIR"
  echo "  │"
  echo "  │  الملفات المُنتجة:"
  echo "  │  ├── atlas-packages.manifest   (قائمة كل الحزم)"
  echo "  │  ├── atlas-first-boot.sh       (اختيار الواجهة تلقائياً)"
  echo "  │  ├── atlas-build-report.html   (تقرير HTML)"
  echo "  │  ├── config/                   (ملفات الإعداد)"
  echo "  │  │   ├── system/               (pacman, mkinitcpio)"
  echo "  │  │   ├── grub/                 (إعدادات GRUB)"
  echo "  │  │   ├── locale/               (اللغة والمنطقة)"
  echo "  │  │   ├── firewall/             (UFW, Fail2Ban)"
  echo "  │  │   ├── backup/               (Timeshift)"
  echo "  │  │   ├── kde/                  (ثيم Windows 11)"
  echo "  │  │   └── xfce/                 (ثيم Windows 11)"
  echo "  │  ├── calamares/               (مثبّت النظام)"
  echo "  │  ├── ventoy/                  (دعم Ventoy + USB)"
  echo "  │  └── airootfs-scripts/        (سكريبتات chroot)"
  echo "  │"
  echo "  │  الوضع المُنفَّذ: $BUILD_MODE"
  echo "  │  عدد الحزم   : $(grep -cE '^[a-zA-Z]' "$MANIFEST_FILE" 2>/dev/null || echo '?')"
  echo "  └─────────────────────────────────────────────────────┘"
  echo -e "${N}"

  if [[ "$BUILD_MODE" == "manifest" ]]; then
    echo -e "${Y}  💡 الخطوة التالية: لبناء ISO فعلي:${N}"
    echo -e "${C}     git clone <this-repo> && cd atlas-linux${N}"
    echo -e "${C}     sudo bash atlas-linux-build.sh --mode iso${N}"
    echo -e "${C}     (يتطلب Arch Linux + root)${N}"
  fi
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# [MAIN]  النقطة الرئيسية  /  Main Entry Point
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
main() {
  show_banner
  setup_dirs

  detect_build_mode
  install_build_deps

  generate_package_manifest
  generate_auto_desktop_script
  generate_configs
  generate_airootfs_scripts
  generate_calamares_config
  generate_ventoy_config
  install_local_apps

  if [[ "$BUILD_MODE" == "iso" ]]; then
    setup_archiso_profile
    build_iso
  fi

  generate_report
  print_error_summary
  print_summary
}

# ─── تشغيل السكريبت ──────────────────────────────────────────
main "$@"
