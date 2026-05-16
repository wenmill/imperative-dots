#!/usr/bin/env bash

# ==============================================================================
# Personal Hyprland install
# Layout/structure adapted from ilyamiro/imperative-dots, modified.
# Changes vs upstream:
#   - All telemetry removed (no WORKER_URL, no send_telemetry, no TELEMETRY_ID)
#   - Added: LiteLLM, Ollama, Hermes Agent, Kavita install + wiring
#   - Added: SDDM Astronaut theme (replaces upstream's matugen-minimal SDDM theme)
#   - Added: AI popup config template
#   - Added packages: quickshell-git, hyprpolkitagent, uwsm, rust, python-pip,
#     nodejs, npm, openssl
# ==============================================================================

# ==============================================================================
# Script Versioning & Initialization
# ==============================================================================
DOTS_VERSION="2.0.0-personal"
VERSION_FILE="$HOME/.local/state/imperative-dots-version"

# ==============================================================================
# Terminal UI Colors & Formatting
# ==============================================================================
RESET="\e[0m"
BOLD="\e[1m"
DIM="\e[2m"
C_BLUE="\e[34m"
C_CYAN="\e[36m"
C_GREEN="\e[32m"
C_YELLOW="\e[33m"
C_RED="\e[31m"
C_MAGENTA="\e[35m"

# ==============================================================================
# Early Distro Detection
# ==============================================================================
if [ -f /etc/os-release ]; then
    DETECTED_OS=$(awk -F= '/^ID=/{gsub(/"/, "", $2); print $2}' /etc/os-release)
else
    echo -e "${C_RED}Cannot detect OS. /etc/os-release not found.${RESET}"
    exit 1
fi

case "$DETECTED_OS" in
    arch|endeavouros|manjaro|cachyos|parch|garuda)
        OS="$DETECTED_OS"
        ;;
    *)
        echo -e "${C_RED}Unsupported OS ($DETECTED_OS). This script supports Arch and derivatives only.${RESET}"
        exit 1
        ;;
esac

# Refuse to run as root — installs go to $HOME
if [ "$(id -u)" -eq 0 ]; then
    echo -e "${C_RED}Don't run as root. The script installs to your normal user's \$HOME.${RESET}"
    exit 1
fi

# Prevent the TTY from sleeping during long builds
setterm -blank 0 -powerdown 0 2>/dev/null || true
printf '\033[9;0]' 2>/dev/null || true

# ==============================================================================
# Global Variables & Initial States
# ==============================================================================
USER_PICTURES_DIR=""

if [ -f "$HOME/.config/user-dirs.dirs" ]; then
    USER_PICTURES_DIR=$(grep '^XDG_PICTURES_DIR' "$HOME/.config/user-dirs.dirs" | cut -d= -f2 | tr -d '"' | sed "s|\$HOME|$HOME|g")
fi
[[ -z "$USER_PICTURES_DIR" || "$USER_PICTURES_DIR" == "$HOME" ]] && USER_PICTURES_DIR="$(xdg-user-dir PICTURES 2>/dev/null)"
[[ -z "$USER_PICTURES_DIR" || "$USER_PICTURES_DIR" == "$HOME" ]] && USER_PICTURES_DIR="$HOME/Pictures"
USER_PICTURES_DIR="${USER_PICTURES_DIR%/}"

USER_VIDEOS_DIR=""
if [ -f "$HOME/.config/user-dirs.dirs" ]; then
    USER_VIDEOS_DIR=$(grep '^XDG_VIDEOS_DIR' "$HOME/.config/user-dirs.dirs" | cut -d= -f2 | tr -d '"' | sed "s|\$HOME|$HOME|g")
fi
[[ -z "$USER_VIDEOS_DIR" || "$USER_VIDEOS_DIR" == "$HOME" ]] && USER_VIDEOS_DIR="$(xdg-user-dir VIDEOS 2>/dev/null)"
[[ -z "$USER_VIDEOS_DIR" || "$USER_VIDEOS_DIR" == "$HOME" ]] && USER_VIDEOS_DIR="$HOME/Videos"
USER_VIDEOS_DIR="${USER_VIDEOS_DIR%/}"

WALLPAPER_DIR="$USER_PICTURES_DIR/Wallpapers"
WEATHER_API_KEY=""
WEATHER_CITY_ID=""
WEATHER_UNIT=""
FAILED_PKGS=()

TARGET_BRANCH="master"
HEADLESS=false

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --dev) TARGET_BRANCH="dev"; shift ;;
        --headless) HEADLESS=true; shift ;;
        *) shift ;;
    esac
done

if [[ "$TARGET_BRANCH" == "dev" ]]; then
    echo -e "${C_YELLOW}[!] RUNNING IN DEVELOPMENT MODE (Branch: dev)${RESET}"
fi
if [[ "$HEADLESS" == "true" ]]; then
    echo -e "${C_YELLOW}[!] HEADLESS MODE — interactive prompts will use defaults${RESET}"
fi

OPT_SDDM=false
OPT_NVIM=false
OPT_ZSH=false
OPT_WALLPAPERS=false
OPT_OVERRIDE_KEYBINDS=false
OPT_OVERRIDE_STARTUPS=false
OPT_AI=true     # AI stack (Ollama + LiteLLM + Hermes) — install by default

INSTALL_NVIM=false
INSTALL_ZSH=false
INSTALL_SDDM=false
REPLACE_DM=false
SETUP_SDDM_THEME=false
SDDM_WAYLAND=false

DRIVER_CHOICE="None (Skipped)"
DRIVER_PKGS=()
HAS_NVIDIA_PROPRIETARY=false
LAST_COMMIT=""
KEEP_OLD_ENV=true

VISITED_PKGS=false
VISITED_OVERVIEW=false
VISITED_WEATHER=false
VISITED_DRIVERS=false
VISITED_KEYBOARD=false

KB_LAYOUTS="us"
KB_LAYOUTS_DISPLAY="English (US)"
KB_OPTIONS="grp:alt_shift_toggle"

mkdir -p "$(dirname "$VERSION_FILE")"

if [ -f "$VERSION_FILE" ] && [ -s "$VERSION_FILE" ]; then
    source "$VERSION_FILE"
    if [ -n "${LOCAL_VERSION:-}" ] && [ "$LOCAL_VERSION" != "Not Installed" ]; then
        [ -n "$KB_LAYOUTS" ] && VISITED_KEYBOARD=true
        [ -n "$WEATHER_API_KEY" ] && VISITED_WEATHER=true
        [[ "$DRIVER_CHOICE" != "None (Skipped)" && -n "$DRIVER_CHOICE" ]] && VISITED_DRIVERS=true
    fi
else
    LOCAL_VERSION="Not Installed"
fi

# ==============================================================================
# Package list — pacman + AUR mixed (the AUR helper handles both)
# ==============================================================================
ARCH_PKGS=(
    # Core compositor + portals + session management
    "hyprland" "hypridle" "hyprlock" "hyprpaper" "hyprpolkitagent" "uwsm"
    "kitty" "cava" "zbar" "pavucontrol" "alsa-utils" "awww" "networkmanager-dmenu-git"
    "wl-clipboard" "fd" "qt6-multimedia" "qt6-5compat" "ripgrep"
    "cliphist" "jq" "socat" "inotify-tools" "pamixer" "brightnessctl" "acpi" "iw"
    "bluez" "bluez-utils" "libnotify" "networkmanager" "lm_sensors" "bc"
    "pipewire" "wireplumber" "pipewire-pulse" "pipewire-alsa" "pipewire-jack" "libpulse" "python"
    "imagemagick" "file" "git" "psmisc"
    "matugen-bin" "ffmpeg" "fastfetch" "quickshell-git" "unzip" "python-websockets" "qt6-websockets"
    "grim" "playerctl" "satty" "yq" "xdg-desktop-portal-gtk" "xdg-desktop-portal-wlr" "slurp" "mpvpaper"
    "wmctrl" "power-profiles-daemon" "easyeffects" "swayosd-git" "nautilus" "lsp-plugins"
    "qt5-wayland" "qt5-quickcontrols" "qt5-quickcontrols2" "qt5-graphicaleffects" "qt6-wayland"
    "qt5ct" "qt6ct" "gpu-screen-recorder" "adw-gtk-theme"
    # libxcb + xcb-util-cursor: needed by Qt's xcb fallback plugin. Even with
    # QT_QPA_PLATFORM=wayland forced, some Qt apps probe xcb at startup and
    # crash if the deps are missing.
    "libxcb" "xcb-util-cursor"
    # AI stack prerequisites
    # Note: python312 (AUR) is used for the LiteLLM venv because LiteLLM proxy
    # has uvloop/fastuuid/orjson build issues on Python 3.13+. System python is
    # left alone — this only affects the LiteLLM virtual environment.
    "python-pip" "python312" "nodejs" "npm" "rust" "openssl"
    # Required for SDDM Astronaut theme
    "qt6-svg" "qt6-declarative" "qt6-virtualkeyboard"
    # Containers
    "podman" "fuse-overlayfs" "slirp4netns"
)

PKGS=("${ARCH_PKGS[@]}")

# ==============================================================================
# TUI bootstrap
# ==============================================================================
if ! command -v fzf &> /dev/null || ! command -v lspci &> /dev/null || ! command -v jq &> /dev/null || ! command -v curl &> /dev/null; then
    echo -e "${C_CYAN}Bootstrapping TUI dependencies (fzf, pciutils, jq, curl)...${RESET}"
    sudo pacman -Sy --noconfirm --needed fzf pciutils jq curl > /dev/null 2>&1
fi

if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
    echo -e "${C_CYAN}Enabling multilib repository for 32-bit driver support...${RESET}"
    sudo sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//}' /etc/pacman.conf
fi

# --- CRITICAL: Full system upgrade BEFORE any package install ---
# Arch is a rolling release and AUR packages built against newer libraries WILL
# fail to install on a partially-upgraded system. Classic failure mode:
#   error: failed to prepare transaction (could not satisfy dependencies)
#   installing libelf (0.195-1) breaks dependency 'libelf=0.194' required by lib32-libelf
# This happens when the main repo has libelf 0.195 but multilib still has the
# 0.194 version. A full -Syu pulls both in lockstep and avoids the conflict.
#
# We do this AFTER enabling multilib so the upgrade also picks up multilib pkgs.
echo -e "${C_CYAN}Performing full system upgrade (required before AUR installs)...${RESET}"
echo -e "${DIM}  This may take a while on stale systems. Skipping this step on Arch${RESET}"
echo -e "${DIM}  causes 'libelf breaks dependency' / 'partial upgrade' failures later.${RESET}"

if ! sudo pacman -Syu --noconfirm; then
    echo -e "${C_RED}Full system upgrade failed.${RESET}"
    echo -e "${C_YELLOW}Common causes:${RESET}"
    echo -e "  1. Stale pacman mirrors — try: ${BOLD}sudo pacman-mirrors --fasttrack${RESET}"
    echo -e "  2. Keyring out of date — try: ${BOLD}sudo pacman -S archlinux-keyring && sudo pacman -Syu${RESET}"
    echo -e "  3. Kernel was updated and modules are mid-rebuild — reboot and retry"
    echo -e "  4. Disk space — ${BOLD}df -h /var/cache/pacman/pkg /${RESET}"
    echo -e "${C_YELLOW}Re-run this script after fixing.${RESET}"
    exit 1
fi

# Refresh keyring after the upgrade in case new signing keys landed
sudo pacman -S --noconfirm --needed archlinux-keyring > /dev/null 2>&1 || true

# AUR helper: paru (written in Rust, no yay/Go).
if ! command -v paru &> /dev/null; then
    echo -e "${C_CYAN}Installing 'paru' (AUR helper, Rust-based)...${RESET}"
    sudo pacman -S --noconfirm --needed base-devel git rust
    tmpdir=$(mktemp -d)
    git clone https://aur.archlinux.org/paru.git "$tmpdir/paru" > /dev/null 2>&1

    # Sanity check the clone
    if ! grep -q '^pkgname=paru$' "$tmpdir/paru/PKGBUILD" 2>/dev/null; then
        rm -rf "$tmpdir"
        echo -e "${C_RED}paru PKGBUILD doesn't look right. Refusing to build.${RESET}"
        exit 1
    fi

    (cd "$tmpdir/paru" && makepkg -si --noconfirm > /dev/null 2>&1)
    rm -rf "$tmpdir"
fi

if command -v paru &> /dev/null; then
    # --sudoloop keeps sudo creds alive during long AUR builds
    # --skipreview skips PKGBUILD review prompt (we sanity-checked paru above; trust the rest)
    PKG_MANAGER="paru -S --noconfirm --needed --sudoloop"
else
    PKG_MANAGER="sudo pacman -S --noconfirm --needed"
fi

# ==============================================================================
# Hardware detection
# ==============================================================================
USER_NAME=$USER
OS_NAME=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2 | tr -d '"')
CPU_INFO=$(grep -m 1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)

GPU_RAW=$(lspci -nn | grep -iE 'vga|3d|display')
GPU_INFO=$(echo "$GPU_RAW" | cut -d: -f3 | sed -E 's/ \(rev [0-9a-f]+\)//g' | xargs)
[[ -z "$GPU_INFO" ]] && GPU_INFO="Unknown / Virtual Machine"

GPU_VENDOR="Unknown / Generic VM"
if echo "$GPU_INFO" | grep -qi "nvidia"; then
    GPU_VENDOR="NVIDIA"
elif echo "$GPU_INFO" | grep -qi "amd\|radeon\|navi"; then
    GPU_VENDOR="AMD"
elif echo "$GPU_INFO" | grep -qi "intel"; then
    GPU_VENDOR="INTEL"
elif echo "$GPU_INFO" | grep -qi "vmware\|virtualbox\|qxl\|virtio\|bochs"; then
    GPU_VENDOR="VM"
fi

EXISTING_SETTINGS="$HOME/.config/hypr/settings.json"
if [ -f "$EXISTING_SETTINGS" ] && command -v jq &>/dev/null; then
    _sj_lang=$(jq -r 'if has("language") then (.language // "") else "IGNORE_ME" end' "$EXISTING_SETTINGS" 2>/dev/null)
    _sj_kbopt=$(jq -r 'if has("kbOptions") then (.kbOptions // "") else "IGNORE_ME" end' "$EXISTING_SETTINGS" 2>/dev/null)
    _sj_wpdir=$(jq -r 'if has("wallpaperDir") then (.wallpaperDir // "") else "IGNORE_ME" end' "$EXISTING_SETTINGS" 2>/dev/null)

    if [[ "$_sj_lang" != "IGNORE_ME" ]]; then
        KB_LAYOUTS="$_sj_lang"
        if [ -z "$KB_LAYOUTS_DISPLAY" ]; then
            KB_LAYOUTS_DISPLAY="$_sj_lang"
        fi
        VISITED_KEYBOARD=true
    fi
    [[ "$_sj_kbopt" != "IGNORE_ME" ]] && KB_OPTIONS="$_sj_kbopt"
    if [[ "$_sj_wpdir" != "IGNORE_ME" ]] && [[ -n "$_sj_wpdir" ]]; then
        _sj_wpdir="${_sj_wpdir%/}"
        WALLPAPER_DIR="$_sj_wpdir"
        USER_PICTURES_DIR="$(dirname "$_sj_wpdir")"
    fi
fi

draw_header() {
    clear
    printf "${BOLD}${C_CYAN}"
    cat << "EOF"
 ██╗    ██╗███████╗███╗   ██╗███╗   ███╗██╗██╗
 ██║    ██║██╔════╝████╗  ██║████╗ ████║██║██║
 ██║ █╗ ██║█████╗  ██╔██╗ ██║██╔████╔██║██║██║
 ██║███╗██║██╔══╝  ██║╚██╗██║██║╚██╔╝██║██║██║
 ╚███╔███╔╝███████╗██║ ╚████║██║ ╚═╝ ██║██║███████╗
  ╚══╝╚══╝ ╚══════╝╚═╝  ╚═══╝╚═╝     ╚═╝╚═╝╚══════╝
EOF
    printf "${RESET}\n"

    printf "\033[K${C_BLUE} -----------------------------------------------------------------${RESET}\n"
    printf "\033[K${BOLD} User:           ${RESET} %s\n" "$USER_NAME"
    printf "\033[K${BOLD} OS:             ${RESET} %s\n" "$OS_NAME"
    printf "\033[K${BOLD} CPU:            ${RESET} %s\n" "$CPU_INFO"
    printf "\033[K${BOLD} GPU:            ${RESET} %s ${DIM}(%s)${RESET}\n" "$GPU_INFO" "$GPU_VENDOR"
    printf "\033[K${C_BLUE} -----------------------------------------------------------------${RESET}\n"
    printf "\033[K${BOLD} Server Version: ${RESET} %s\n" "$DOTS_VERSION"
    printf "\033[K${BOLD} Local Version:  ${RESET} %s\n" "${LOCAL_VERSION:-Not Installed}"
    printf "\033[K${C_BLUE} =================================================================${RESET}\n\n"
}

manage_packages() {
    while true; do
        draw_header
        local action
        action=$(echo -e "1. View Packages to be Installed\n2. Add Custom Packages\n3. Back to Main Menu" | fzf \
            --layout=reverse --border=rounded --margin=1,2 --height=15 \
            --prompt=" Package Manager > " --pointer=">" \
            --header=" Use ARROW KEYS and ENTER ")

        case "$action" in
            *"1"*)
                echo "${PKGS[@]}" | tr ' ' '\n' | fzf \
                    --layout=reverse --border=rounded --margin=1,2 --height=25 \
                    --prompt=" Current Packages > " --pointer=">" \
                    --header=" Press ESC or ENTER to return to menu "
                ;;
            *"2"*)
                echo -e "${C_CYAN}Enter package names (separated by space) ${BOLD}[Empty to cancel]${RESET}${C_CYAN}:${RESET}"
                read -r new_pkgs
                if [ -n "$new_pkgs" ]; then
                    PKGS+=($new_pkgs)
                    echo -e "${C_GREEN}Packages added!${RESET}"
                    sleep 1
                fi
                ;;
            *"3"*) VISITED_PKGS=true; break ;;
            *) VISITED_PKGS=true; break ;;
        esac
    done
}

manage_drivers() {
    while true; do
        draw_header
        echo -e "${BOLD}${C_CYAN}=== Hardware Driver Configuration ===${RESET}"
        echo -e "${BOLD}${C_RED}=================== EXPERIMENTAL WARNING ===================${RESET}"
        echo -e "${C_RED}This automated driver installer is highly experimental and${RESET}"
        echo -e "${C_RED}can be unreliable across different kernel/distro variations.${RESET}"
        echo -e "${C_RED}It is strongly recommended to SKIP this and install your${RESET}"
        echo -e "${C_RED}graphics drivers manually according to your distro's wiki.${RESET}"
        echo -e "${BOLD}${C_RED}============================================================${RESET}\n"
        echo -e "Detected GPU Vendor: ${BOLD}${C_YELLOW}$GPU_VENDOR${RESET}\n"

        # RDNA4 detection (RX 9070, 9060 XT)
        if echo "$GPU_INFO" | grep -qiE "navi 4|rx 90[67]0|rx 9060"; then
            echo -e "${C_YELLOW}[!] RDNA4 (Navi 4x) detected — needs kernel 6.12+ and Mesa 25.0+${RESET}"
            kernel_ver=$(uname -r | cut -d. -f1,2)
            echo -e "${C_YELLOW}[!] Current kernel: $(uname -r)${RESET}"
            if [ "$(printf '%s\n' "6.12" "$kernel_ver" | sort -V | head -1)" != "6.12" ]; then
                echo -e "${C_RED}[!] Kernel may be too old. Consider: sudo pacman -S linux${RESET}"
            fi
            echo
        fi

        local current_driver="None"
        if command -v lsmod &> /dev/null; then
            if lsmod | grep -wq nvidia; then current_driver="nvidia"
            elif lsmod | grep -wq nouveau; then current_driver="nouveau"
            elif lsmod | grep -Ewq "amdgpu|radeon"; then current_driver="amd"
            elif lsmod | grep -Ewq "i915|xe"; then current_driver="intel"
            fi
        fi

        local options=""
        case "$GPU_VENDOR" in
            "NVIDIA")
                if [[ "$current_driver" == "nouveau" ]]; then
                    echo -e "${C_YELLOW}[!] Notice: Open-source 'nouveau' drivers are currently loaded.${RESET}"
                    echo -e "${C_RED}[!] Proprietary installation is locked out to prevent initramfs conflicts.${RESET}\n"
                    options="1. Update/Keep Nouveau (Open Source)\n2. Skip Driver Installation"
                elif [[ "$current_driver" == "nvidia" ]]; then
                    echo -e "${C_YELLOW}[!] Notice: Proprietary 'nvidia' drivers are currently loaded.${RESET}"
                    echo -e "${C_RED}[!] Open-source installation is locked out to prevent conflicts.${RESET}\n"
                    options="1. Update/Keep Proprietary NVIDIA Drivers\n2. Skip Driver Installation"
                else
                    options="1. Install Proprietary NVIDIA Drivers (Recommended for Gaming/Wayland)\n2. Install Nouveau (Open Source, Better VM compat)\n3. Skip Driver Installation"
                fi
                ;;
            "AMD") options="1. Install AMD Mesa & Vulkan Drivers (RADV)\n2. Skip Driver Installation" ;;
            "INTEL") options="1. Install Intel Mesa & Vulkan Drivers (ANV)\n2. Skip Driver Installation" ;;
            *) options="1. Install Generic Mesa Drivers (For VMs / Software Rendering)\n2. Skip Driver Installation" ;;
        esac

        local choice
        choice=$(echo -e "$options\nBack to Main Menu" | fzf \
            --ansi --layout=reverse --border=rounded --margin=1,2 --height=15 \
            --prompt=" Drivers > " --pointer=">" \
            --header=" Select the graphics drivers to install ")

        if [[ "$choice" == *"Back"* ]]; then break; fi

        if [[ "$choice" != *"Skip"* ]]; then
            echo -e "\n${BOLD}${C_RED}=================== ACTION REQUIRED ===================${RESET}"
            echo -e "${C_YELLOW}You have selected to AUTOMATICALLY install/configure drivers.${RESET}"
            echo -e "${C_YELLOW}If your system already has working drivers, this might break boot.${RESET}"
            echo -n -e "Are you ${BOLD}${C_RED}100% sure${RESET} you want to proceed? (y/n): "
            read -r confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                echo -e "\n${C_RED}Driver setup aborted. Returning to menu...${RESET}"
                sleep 1.2
                continue
            fi
        fi

        DRIVER_PKGS=()
        HAS_NVIDIA_PROPRIETARY=false

        if [[ "$choice" == *"Proprietary NVIDIA"* ]]; then
            DRIVER_CHOICE="NVIDIA Proprietary"
            HAS_NVIDIA_PROPRIETARY=true
            DRIVER_PKGS+=("nvidia-dkms" "nvidia-utils" "lib32-nvidia-utils" "linux-headers" "egl-wayland")
        elif [[ "$choice" == *"Nouveau"* ]]; then
            DRIVER_CHOICE="NVIDIA Nouveau"
            DRIVER_PKGS+=("mesa" "vulkan-nouveau" "lib32-mesa")
        elif [[ "$choice" == *"AMD"* ]]; then
            DRIVER_CHOICE="AMD Drivers"
            DRIVER_PKGS+=("mesa" "vulkan-radeon" "lib32-vulkan-radeon" "lib32-mesa" "xf86-video-amdgpu" "linux-firmware")
        elif [[ "$choice" == *"Intel"* ]]; then
            DRIVER_CHOICE="Intel Drivers"
            DRIVER_PKGS+=("mesa" "vulkan-intel" "lib32-vulkan-intel" "lib32-mesa" "intel-media-driver")
        elif [[ "$choice" == *"Generic"* ]]; then
            DRIVER_CHOICE="Generic / VM"
            # virglrenderer + libva-mesa = best chance of getting a working render
            # node inside a VM. Still requires the *host* to enable virtio-gl
            # (Proxmox: 'qm set <vmid> --vga virtio-gl'). Without that the VM
            # has no usable DRM render node and Hyprland will fail with
            # "no matching devices found" in aquamarine.
            DRIVER_PKGS+=("mesa" "lib32-mesa" "virglrenderer" "libva-mesa-driver" "mesa-vdpau")
        elif [[ "$choice" == *"Skip"* ]]; then
            DRIVER_CHOICE="Skipped"
            DRIVER_PKGS=()
        fi

        echo -e "\n${C_GREEN}Driver configuration saved!${RESET}"
        sleep 1.2
        VISITED_DRIVERS=true
        break
    done
}

manage_keyboard() {
    local available_layouts=(
        "us - English (US)" "ca - English/French (Canada)" "ca-multix - Canadian Multilingual"
        "latam - Spanish (Latin America)" "br - Portuguese (Brazil)"
        "gb - English (UK)" "ie - English (Ireland)"
        "fr - French" "be - Belgian" "ch - Swiss" "de - German" "at - Austrian"
        "nl - Dutch" "lu - Luxembourgish" "es - Spanish" "pt - Portuguese"
        "it - Italian" "se - Swedish" "no - Norwegian" "dk - Danish" "fi - Finnish"
        "pl - Polish" "cz - Czech" "sk - Slovak" "hu - Hungarian"
        "ru - Russian" "ua - Ukrainian" "by - Belarusian" "ro - Romanian" "bg - Bulgarian"
        "rs - Serbian" "hr - Croatian" "si - Slovenian" "gr - Greek"
        "ee - Estonian" "lv - Latvian" "lt - Lithuanian"
        "cn - Chinese" "jp - Japanese" "kr - Korean" "tw - Taiwanese"
        "in - Indian" "th - Thai" "vn - Vietnamese"
        "il - Hebrew" "ara - Arabic" "ir - Persian (Farsi)"
        "us-intl - US International" "dvorak - US Dvorak" "colemak - US Colemak"
    )

    local selected_codes=()
    local selected_names=()

    if [[ -n "$KB_LAYOUTS" ]]; then
        IFS=',' read -ra tmp_codes <<< "$KB_LAYOUTS"
        for code in "${tmp_codes[@]}"; do selected_codes+=("$(echo "$code" | xargs)"); done
    else
        selected_codes=("us")
    fi
    if [[ -n "$KB_LAYOUTS_DISPLAY" ]]; then
        IFS=',' read -ra tmp_names <<< "$KB_LAYOUTS_DISPLAY"
        for name in "${tmp_names[@]}"; do selected_names+=("$(echo "$name" | xargs)"); done
    else
        selected_names=("English (US)")
    fi

    while true; do
        draw_header
        echo -e "${BOLD}${C_CYAN}=== Keyboard Layout Configuration ===${RESET}\n"

        if [ ${#selected_codes[@]} -gt 0 ]; then
            echo -e "Currently added: ${C_GREEN}$(IFS=', '; echo "${selected_names[*]}")${RESET}\n"
        fi

        local choice
        choice=$(printf "%s\n" "Done (Finish Selection)" "Reset (Clear All Except US)" "${available_layouts[@]}" | fzf \
            --layout=reverse --border=rounded --margin=1,2 --height=20 \
            --prompt=" Add Layout > " --pointer=">" \
            --header=" Select a language to add, or select Done ")

        if [[ -z "$choice" || "$choice" == *"Done"* ]]; then break; fi

        if [[ "$choice" == *"Reset"* ]]; then
            selected_codes=("us")
            selected_names=("English (US)")
            continue
        fi

        local code=$(echo "$choice" | awk '{print $1}')
        local name=$(echo "$choice" | cut -d'-' -f2- | sed 's/^ //')

        local duplicate=false
        for existing in "${selected_codes[@]}"; do
            [[ "$existing" == "$code" ]] && duplicate=true && break
        done
        if [ "$duplicate" = false ]; then
            selected_codes+=("$code")
            selected_names+=("$name")
        fi
    done

    while true; do
        draw_header
        echo -e "${BOLD}${C_CYAN}=== Keyboard Layout Configuration ===${RESET}\n"
        echo -e "Currently added: ${C_GREEN}$(IFS=', '; echo "${selected_names[*]}")${RESET}\n"
        echo -e "${C_CYAN}Choose a key combination to switch between layouts:${RESET}"

        local options="1. Alt + Shift (grp:alt_shift_toggle)\n"
        options+="2. Win + Space (grp:win_space_toggle)\n"
        options+="3. Caps Lock (grp:caps_toggle)\n"
        options+="4. Ctrl + Shift (grp:ctrl_shift_toggle)\n"
        options+="5. Ctrl + Alt (grp:ctrl_alt_toggle)\n"
        options+="6. Right Alt (grp:toggle)\n"
        options+="7. No Toggle (Single Layout)"

        local choice
        choice=$(echo -e "$options" | fzf \
            --ansi --layout=reverse --border=rounded --margin=1,2 --height=15 \
            --prompt=" Toggle Keybind > " --pointer=">" \
            --header=" Select layout switching method ")

        local kb_opt=""
        case "$choice" in
            *"1"*) kb_opt="grp:alt_shift_toggle" ;;
            *"2"*) kb_opt="grp:win_space_toggle" ;;
            *"3"*) kb_opt="grp:caps_toggle" ;;
            *"4"*) kb_opt="grp:ctrl_shift_toggle" ;;
            *"5"*) kb_opt="grp:ctrl_alt_toggle" ;;
            *"6"*) kb_opt="grp:toggle" ;;
            *"7"*) kb_opt="" ;;
            *) kb_opt="grp:alt_shift_toggle" ;;
        esac

        KB_LAYOUTS=$(IFS=','; echo "${selected_codes[*]}")
        KB_LAYOUTS_DISPLAY=$(IFS=', '; echo "${selected_names[*]}")
        KB_OPTIONS="$kb_opt"

        echo -e "\n${C_GREEN}Keyboard configured: Layouts = $KB_LAYOUTS_DISPLAY | Switch = ${KB_OPTIONS:-None}${RESET}"
        sleep 1.5
        VISITED_KEYBOARD=true
        break
    done
}

show_overview() {
    draw_header
    echo -e "${BOLD}${C_MAGENTA}=== System Overview & Keybinds ===${RESET}\n"
    echo -e "Personal Hyprland setup based on the ${BOLD}${C_CYAN}ilyamiro/imperative-dots${RESET} structure.\n"

    print_kb() {
        printf "  ${C_CYAN}[${RESET} ${BOLD}%-17s${RESET} ${C_CYAN}]${RESET}  ${C_YELLOW}➜${RESET}  %s\n" "$1" "$2"
    }

    echo -e "${BOLD}${C_BLUE}--- Applications ---${RESET}"
    print_kb "SUPER + RETURN" "Open Terminal (kitty)"
    print_kb "SUPER + D" "Open App Launcher"
    print_kb "SUPER + F" "Open Browser"
    print_kb "SUPER + E" "Open File Manager"
    print_kb "SUPER + C" "Clipboard History"
    echo ""
    echo -e "${BOLD}${C_BLUE}--- Quickshell Widgets ---${RESET}"
    print_kb "SUPER + M" "Toggle Monitors"
    print_kb "SUPER + Q" "Toggle Music"
    print_kb "SUPER + B" "Toggle Battery"
    print_kb "SUPER + W" "Toggle Wallpaper"
    print_kb "SUPER + S" "Toggle Calendar"
    print_kb "SUPER + N" "Toggle Network"
    print_kb "SUPER + SHIFT + T" "Toggle FocusTime"
    print_kb "SUPER + V" "Toggle Volume Control"
    print_kb "SUPER + comma" "Toggle System Settings"
    print_kb "SUPER + A" "Toggle AI popup"
    echo ""
    echo -e "${BOLD}${C_BLUE}--- AI / LiteLLM / Hermes ---${RESET}"
    print_kb "ai_config.json" "API key, model, lichess + kavita keys"
    print_kb "LiteLLM" "http://localhost:4000 (key in ai_config.json)"
    print_kb "Hermes" "Approval-based shell tool execution"
    echo ""
    echo -e "${BOLD}${C_GREEN}Press ENTER to return to the Main Menu...${RESET}"
    read -r
    VISITED_OVERVIEW=true
}

set_weather_api() {
    while true; do
        draw_header
        echo -e "${BOLD}${C_CYAN}=== OpenWeatherMap Setup ===${RESET}"

        ENV_FILE="$HOME/.config/hypr/scripts/quickshell/calendar/.env"

        if [ -f "$ENV_FILE" ] || [[ -n "$WEATHER_API_KEY" && "$WEATHER_API_KEY" != "Skipped" ]]; then
            echo -e "${C_GREEN}Existing config detected. Press ENTER without typing to KEEP it.${RESET}\n"
        else
            echo -e "${C_MAGENTA}Get a free API key at https://openweathermap.org/${RESET}\n"
        fi

        read -p "OpenWeather API Key (or Enter to skip/keep): " input_key

        if [[ -z "$input_key" ]]; then
            if [ -f "$ENV_FILE" ] || [[ -n "$WEATHER_API_KEY" && "$WEATHER_API_KEY" != "Skipped" ]]; then
                KEEP_OLD_ENV=true
                VISITED_WEATHER=true
                break
            else
                WEATHER_API_KEY="Skipped"
                KEEP_OLD_ENV=false
                VISITED_WEATHER=true
                break
            fi
        fi

        WEATHER_API_KEY="$(echo "$input_key" | tr -d ' ')"
        read -p "City ID (number from openweathermap.org URL): " input_id
        if [[ -z "$input_id" || ! "$input_id" =~ ^[0-9]+$ ]]; then
            echo -e "${C_RED}Invalid City ID.${RESET}"
            sleep 1
            continue
        fi
        WEATHER_CITY_ID="$input_id"

        unit_choice=$(echo -e "metric (Celsius)\nimperial (Fahrenheit)\nstandard (Kelvin)" | fzf \
            --layout=reverse --border=rounded --margin=1,2 --height=12 \
            --prompt=" Unit > " --pointer=">" --header=" Choose unit ")
        WEATHER_UNIT=$(echo "$unit_choice" | awk '{print $1}')
        [[ -z "$WEATHER_UNIT" ]] && WEATHER_UNIT="metric"

        KEEP_OLD_ENV=false
        VISITED_WEATHER=true
        break
    done
}

manage_ai_stack() {
    while true; do
        draw_header
        echo -e "${BOLD}${C_CYAN}=== AI Stack Configuration ===${RESET}\n"
        echo -e "Installs and wires together:"
        echo -e "  ${C_GREEN}Ollama${RESET}    — local model server (port 11434)"
        echo -e "  ${C_GREEN}LiteLLM${RESET}   — OpenAI-compatible router (port 4000)"
        echo -e "  ${C_GREEN}Hermes${RESET}    — agent that uses LiteLLM/Ollama for tool calls\n"

        local current="$( [ "$OPT_AI" = true ] && echo -e "${C_GREEN}ENABLED${RESET}" || echo -e "${DIM}DISABLED${RESET}" )"
        echo -e "Current: ${BOLD}$current${RESET}\n"

        local action
        action=$(echo -e "1. Enable AI Stack\n2. Disable AI Stack\n3. Back" | fzf \
            --layout=reverse --border=rounded --margin=1,2 --height=12 \
            --prompt=" AI Stack > " --pointer=">" --header=" ")

        case "$action" in
            *"1"*) OPT_AI=true; break ;;
            *"2"*) OPT_AI=false; break ;;
            *) break ;;
        esac
    done
}

prompt_optional_features_menu() {
    DM_SERVICES=("gdm" "gdm3" "lightdm" "sddm" "lxdm" "lxdm-gtk3" "ly")
    CURRENT_DM=""
    for dm in "${DM_SERVICES[@]}"; do
        if systemctl is-enabled "$dm.service" &>/dev/null || systemctl is-active "$dm.service" &>/dev/null; then
            CURRENT_DM="$dm"
            break
        fi
    done

    local DM_LABEL="Display Manager Integration (SDDM + Astronaut)"
    if [[ "$CURRENT_DM" == "sddm" ]]; then
        DM_LABEL="Configure SDDM Astronaut Theme"
    elif [[ -n "$CURRENT_DM" ]]; then
        DM_LABEL="Replace $CURRENT_DM with SDDM (Astronaut theme)"
    fi

    local HAS_HISTORY=false
    if [ "$LOCAL_VERSION" != "Not Installed" ] && [ -n "$LOCAL_VERSION" ]; then
        HAS_HISTORY=true
    fi

    while true; do
        draw_header
        echo -e "${BOLD}${C_CYAN}=== Optional Component Setup ===${RESET}\n"

        local S_SDDM=$( [ "$OPT_SDDM" = true ] && echo -e "${C_GREEN}[✓]${RESET}" || echo -e "${DIM}[ ]${RESET}" )
        local S_NVIM=$( [ "$OPT_NVIM" = true ] && echo -e "${C_GREEN}[✓]${RESET}" || echo -e "${DIM}[ ]${RESET}" )
        local S_ZSH=$( [ "$OPT_ZSH" = true ] && echo -e "${C_GREEN}[✓]${RESET}" || echo -e "${DIM}[ ]${RESET}" )
        local S_WP=$( [ "$OPT_WALLPAPERS" = true ] && echo -e "${C_GREEN}[✓]${RESET}" || echo -e "${DIM}[ ]${RESET}" )
        local S_AI=$( [ "$OPT_AI" = true ] && echo -e "${C_GREEN}[✓]${RESET}" || echo -e "${DIM}[ ]${RESET}" )

        local MENU_ITEMS="1. $S_SDDM $DM_LABEL\n"
        MENU_ITEMS+="2. $S_NVIM Neovim Matugen Configuration\n"
        MENU_ITEMS+="3. $S_ZSH Zsh Shell Setup\n"
        MENU_ITEMS+="4. $S_WP Download FULL Wallpaper Pack (Unchecked = 3 Random)\n"
        MENU_ITEMS+="5. $S_AI AI Stack (Ollama + LiteLLM + Hermes)\n"

        if [ "$HAS_HISTORY" = true ]; then
            local S_KB_OVR=$( [ "$OPT_OVERRIDE_KEYBINDS" = true ] && echo -e "${C_GREEN}[✓]${RESET}" || echo -e "${DIM}[ ]${RESET}" )
            local S_STARTUPS_OVR=$( [ "$OPT_OVERRIDE_STARTUPS" = true ] && echo -e "${C_GREEN}[✓]${RESET}" || echo -e "${DIM}[ ]${RESET}" )
            MENU_ITEMS+="6. $S_KB_OVR Reset local keybinds to upstream defaults\n"
            MENU_ITEMS+="7. $S_STARTUPS_OVR Overwrite Local Startups\n"
            MENU_ITEMS+="8. ${BOLD}${C_GREEN}Proceed with Installation / Update${RESET}\n"
            MENU_ITEMS+="9. ${DIM}Back to Main Menu${RESET}"
        else
            OPT_OVERRIDE_KEYBINDS=false
            OPT_OVERRIDE_STARTUPS=false
            MENU_ITEMS+="6. ${BOLD}${C_GREEN}Proceed with Installation / Update${RESET}\n"
            MENU_ITEMS+="7. ${DIM}Back to Main Menu${RESET}"
        fi

        local choice
        choice=$(echo -e "$MENU_ITEMS" | fzf \
            --ansi --layout=reverse --border=rounded --margin=1,2 --height=18 \
            --prompt=" Options > " --pointer=">" \
            --header=" SPACE or ENTER to toggle. Select Proceed when ready. ")

        local break_and_proceed=false

        case "$choice" in
            *"1."*) OPT_SDDM=$([ "$OPT_SDDM" = true ] && echo false || echo true) ;;
            *"2."*) OPT_NVIM=$([ "$OPT_NVIM" = true ] && echo false || echo true) ;;
            *"3."*) OPT_ZSH=$([ "$OPT_ZSH" = true ] && echo false || echo true) ;;
            *"4."*) OPT_WALLPAPERS=$([ "$OPT_WALLPAPERS" = true ] && echo false || echo true) ;;
            *"5."*) OPT_AI=$([ "$OPT_AI" = true ] && echo false || echo true) ;;
            *"6."*)
                if [ "$HAS_HISTORY" = true ]; then
                    OPT_OVERRIDE_KEYBINDS=$([ "$OPT_OVERRIDE_KEYBINDS" = true ] && echo false || echo true)
                else
                    break_and_proceed=true
                fi
                ;;
            *"7."*)
                if [ "$HAS_HISTORY" = true ]; then
                    OPT_OVERRIDE_STARTUPS=$([ "$OPT_OVERRIDE_STARTUPS" = true ] && echo false || echo true)
                else
                    return 1
                fi
                ;;
            *"8."*) [ "$HAS_HISTORY" = true ] && break_and_proceed=true ;;
            *"9."*) [ "$HAS_HISTORY" = true ] && return 1 ;;
            *) ;;
        esac

        if [ "$break_and_proceed" = true ]; then
            if [ "$OPT_SDDM" = true ]; then
                if [[ -z "$CURRENT_DM" ]]; then
                    INSTALL_SDDM=true
                    SETUP_SDDM_THEME=true
                    PKGS+=("sddm")
                elif [[ "$CURRENT_DM" == "sddm" ]]; then
                    SETUP_SDDM_THEME=true
                else
                    INSTALL_SDDM=true
                    REPLACE_DM=true
                    SETUP_SDDM_THEME=true
                    PKGS+=("sddm")
                fi

                clear
                draw_header
                echo -e "${BOLD}${C_CYAN}=== SDDM Configuration ===${RESET}\n"
                echo -e "Force SDDM to run natively on Wayland?"
                echo -e "${DIM}(Default No — safer for NVIDIA setups.)${RESET}"
                read -p "Wayland backend? (y/N): " sddm_wayland
                [[ "$sddm_wayland" =~ ^[Yy]$ ]] && SDDM_WAYLAND=true || SDDM_WAYLAND=false
            fi
            [ "$OPT_NVIM" = true ] && { INSTALL_NVIM=true; PKGS+=("neovim" "lua-language-server" "unzip" "nodejs" "npm" "python3"); }
            [ "$OPT_ZSH" = true ] && { INSTALL_ZSH=true; PKGS+=("zsh"); }
            return 0
        fi
    done
}

# ==============================================================================
# Headless mode shortcut — skip interactive menus, use defaults
# ==============================================================================
if [ "$HEADLESS" = "true" ]; then
    VISITED_KEYBOARD=true
    OPT_AI=true
    OPT_SDDM=true
    INSTALL_SDDM=true
    SETUP_SDDM_THEME=true
    PKGS+=("sddm")
    DRIVER_CHOICE="Skipped (headless)"
    KEEP_OLD_ENV=true
    WEATHER_API_KEY="Skipped"
fi

# ==============================================================================
# Main Menu Loop (skipped in --headless)
# ==============================================================================
if [ "$HEADLESS" = "false" ]; then
while true; do
    draw_header

    S_PKG=$( [ "$VISITED_PKGS" = true ] && echo -e "${C_GREEN}[✓]${RESET}" || echo -e "${C_YELLOW}[-]${RESET}" )
    S_OVW=$( [ "$VISITED_OVERVIEW" = true ] && echo -e "${C_GREEN}[✓]${RESET}" || echo -e "${C_YELLOW}[-]${RESET}" )
    S_WTH=$( [ "$VISITED_WEATHER" = true ] && echo -e "${C_GREEN}[✓]${RESET}" || echo -e "${C_YELLOW}[-]${RESET}" )
    S_DRV=$( [ "$VISITED_DRIVERS" = true ] && echo -e "${C_GREEN}[✓]${RESET}" || echo -e "${C_YELLOW}[-]${RESET}" )
    S_KBD=$( [ "$VISITED_KEYBOARD" = true ] && echo -e "${C_GREEN}[✓]${RESET}" || echo -e "${C_RED}[ ]${RESET}" )
    S_AI=$(  [ "$OPT_AI" = true ] && echo -e "${C_GREEN}[ON]${RESET}" || echo -e "${DIM}[OFF]${RESET}" )

    if [[ -z "$WEATHER_API_KEY" ]]; then
        if [ -f "$HOME/.config/hypr/scripts/quickshell/calendar/.env" ]; then
            API_DISPLAY="Set (from .env file)"
        else
            API_DISPLAY="Not Set"
        fi
    elif [[ "$WEATHER_API_KEY" == "Skipped" ]]; then API_DISPLAY="Skipped"
    else API_DISPLAY="Set ($WEATHER_UNIT, ID: $WEATHER_CITY_ID)"; fi

    if [ "$LOCAL_VERSION" != "Not Installed" ] && [ -n "$LOCAL_VERSION" ]; then
        INSTALL_LABEL="UPDATE"
    else
        INSTALL_LABEL="START"
    fi

    MENU_ITEMS="1. $S_PKG ${C_GREEN}Manage Packages${RESET} [${#PKGS[@]} queued, Optional]\n"
    MENU_ITEMS+="2. $S_OVW ${C_CYAN}Overview & Keybinds${RESET} [Optional]\n"
    MENU_ITEMS+="3. $S_WTH ${C_YELLOW}Set Weather API Key${RESET} [${API_DISPLAY}, Optional]\n"
    MENU_ITEMS+="4. $S_DRV ${C_RED}[ DRIVERS ] Setup${RESET} [${DRIVER_CHOICE}, Optional]\n"
    MENU_ITEMS+="5. $S_KBD ${C_BLUE}Keyboard Layout Setup${RESET} [${KB_LAYOUTS_DISPLAY:-$KB_LAYOUTS}]\n"
    MENU_ITEMS+="6. $S_AI ${C_MAGENTA}AI Stack Settings${RESET}\n"
    MENU_ITEMS+="7. ${BOLD}${C_MAGENTA}${INSTALL_LABEL}${RESET}\n"
    MENU_ITEMS+="8. ${DIM}Exit${RESET}"

    MENU_OPTION=$(echo -e "$MENU_ITEMS" | fzf \
        --ansi --layout=reverse --border=rounded --margin=1,2 --height=17 \
        --prompt=" Main Menu > " --pointer=">" \
        --header=" Navigate with ARROWS. Select with ENTER. ")

    case "$MENU_OPTION" in
        *"1."*) manage_packages ;;
        *"2."*) show_overview ;;
        *"3."*) set_weather_api ;;
        *"4."*) manage_drivers ;;
        *"5."*) manage_keyboard ;;
        *"6."*) manage_ai_stack ;;
        *"7."*)
            if [ "$VISITED_KEYBOARD" = false ]; then
                echo -e "\n${C_RED}[!] Configure your Keyboard Layouts first.${RESET}"
                sleep 2.5
                continue
            fi
            if prompt_optional_features_menu; then break; else continue; fi
            ;;
        *"8."*) clear; exit 0 ;;
        *) exit 0 ;;
    esac
done
fi

# ==============================================================================
# Installation Process
# ==============================================================================
clear
draw_header
echo -e "${BOLD}${C_BLUE}::${RESET} ${BOLD}Starting Installation Process...${RESET}\n"

echo -e "${C_CYAN}[ INFO ]${RESET} Requesting sudo privileges..."
sudo -v

# Sudo keepalive
( while true; do sudo -n true 2>/dev/null; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &
SUDO_PID=$!
trap 'kill $SUDO_PID 2>/dev/null || true' EXIT

# --- 0. Resolve Package Conflicts ---
echo -e "\n${C_CYAN}[ INFO ]${RESET} Resolving potential package conflicts..."

for jack_pkg in jack jack2 jack2-dbus; do
    if pacman -Qq "$jack_pkg" &>/dev/null; then
        echo -e "  -> Removing conflicting package '$jack_pkg'..."
        sudo pacman -Rdd --noconfirm "$jack_pkg" 2>/dev/null || true
    fi
done
yes "Y" | $PKG_MANAGER pipewire-jack > /dev/null 2>&1 || true

CONFLICTING_PKGS=("swayosd" "quickshell" "matugen" "go-yq")
for cpkg in "${CONFLICTING_PKGS[@]}"; do
    if pacman -Qq | grep -qx "$cpkg"; then
        echo -e "  -> ${C_YELLOW}Removing conflicting package '$cpkg'...${RESET}"
        systemctl --user stop "$cpkg" 2>/dev/null || true
        sudo systemctl stop "$cpkg" 2>/dev/null || true

        if ! sudo pacman -Rns --noconfirm "$cpkg" > /dev/null 2>&1; then
            sudo pacman -Rdd --noconfirm "$cpkg" > /dev/null 2>&1
        fi
    fi
done

ALL_PKGS=("${PKGS[@]}" "${DRIVER_PKGS[@]}")
MISSING_PKGS=()

echo -e "\n${C_CYAN}[ INFO ]${RESET} Checking for already installed packages..."
for pkg in "${ALL_PKGS[@]}"; do
    [[ -z "$pkg" ]] && continue
    if pacman -Q "$pkg" &>/dev/null; then
        true
    else
        MISSING_PKGS+=("$pkg")
    fi
done

# --- 1. Install Dependencies & Drivers ---
if [ ${#MISSING_PKGS[@]} -eq 0 ]; then
    echo -e "  -> ${C_GREEN}All packages already installed!${RESET}\n"
else
    echo -e "  -> ${C_YELLOW}Found ${#MISSING_PKGS[@]} missing packages.${RESET}"
    echo -e "\n${C_CYAN}[ INFO ]${RESET} Installing System Packages & Drivers...\n"

    for pkg in "${MISSING_PKGS[@]}"; do
        echo -e "\n${C_CYAN}=================================================================${RESET}"
        echo -e "${C_BLUE}::${RESET} ${BOLD}Installing ${pkg}...${RESET}"
        echo -e "${C_CYAN}=================================================================${RESET}"

        SAFE_JOBS=$(( $(nproc) / 2 ))
        [[ $SAFE_JOBS -lt 1 ]] && SAFE_JOBS=1
        [[ $SAFE_JOBS -gt 4 ]] && SAFE_JOBS=4

        # Capture output so we can detect partial-upgrade dependency errors and
        # surface them clearly. Without this, the user sees [FAILED] with no clue.
        pkg_log=$(mktemp)
        if yes "Y" | env CARGO_BUILD_JOBS="$SAFE_JOBS" MAKEFLAGS="-j$SAFE_JOBS" \
                $PKG_MANAGER "$pkg" 2>&1 | tee "$pkg_log"; then
            echo -e "\n${C_GREEN}[ OK ] Successfully installed ${pkg}${RESET}"
        else
            echo -e "\n${C_RED}[ FAILED ] Failed to install ${pkg}${RESET}"

            # Detect partial-upgrade dependency conflict (lib32-X vs X version mismatch)
            if grep -qE "breaks dependency.*lib32-|installing .* breaks dependency" "$pkg_log"; then
                broken_dep=$(grep -oE "'[a-z0-9-]+=[0-9.]+' required by [a-z0-9-]+" "$pkg_log" | head -1)
                echo -e "${C_YELLOW}  → Partial-upgrade conflict detected: $broken_dep${RESET}"
                echo -e "${C_YELLOW}  → Multilib repo is out of sync with main. Options:${RESET}"
                echo -e "    1. Wait 24h for multilib to catch up, then re-run this script"
                echo -e "    2. Run ${BOLD}sudo pacman -Syu${RESET} again manually and retry"
                echo -e "    3. Temporarily remove the lib32-* package, install $pkg, then reinstall lib32-*"
            elif grep -qE "signature.*unknown trust|key.*could not be looked up" "$pkg_log"; then
                echo -e "${C_YELLOW}  → Signature/keyring issue. Try:${RESET}"
                echo -e "    ${BOLD}sudo pacman -S archlinux-keyring && sudo pacman -Syu${RESET}"
            elif grep -qE "unable to lock database|could not lock database" "$pkg_log"; then
                echo -e "${C_YELLOW}  → Pacman database is locked (another pacman/paru running?).${RESET}"
                echo -e "    Wait for the other process to finish, or if none exists:"
                echo -e "    ${BOLD}sudo rm /var/lib/pacman/db.lck${RESET}"
            elif grep -qE "out of memory|cannot allocate memory|Killed" "$pkg_log"; then
                echo -e "${C_YELLOW}  → Build ran out of memory. Reduce parallel jobs or add swap.${RESET}"
            fi

            FAILED_PKGS+=("$pkg")
        fi
        rm -f "$pkg_log"
        sleep 0.5
    done
fi

# Hyprland is non-negotiable
if ! pacman -Q hyprland &>/dev/null; then
    echo -e "${C_RED}[ ERR ] Hyprland did not install. Cannot continue.${RESET}"
    exit 1
fi

# --- 1.5. NVIDIA Initialization ---
if [ "$HAS_NVIDIA_PROPRIETARY" = true ]; then
    echo -e "\n${C_CYAN}[ INFO ]${RESET} Performing NVIDIA Initialization for Wayland..."
    echo -e "options nvidia-drm modeset=1 fbdev=1" | sudo tee /etc/modprobe.d/nvidia.conf > /dev/null

    if command -v mkinitcpio &> /dev/null; then
        sudo mkinitcpio -P >/dev/null 2>&1
        printf "  -> Mkinitcpio rebuild successful %-9s ${C_GREEN}[ OK ]${RESET}\n" ""
    elif command -v dracut &> /dev/null; then
        sudo dracut --force >/dev/null 2>&1
        printf "  -> Dracut rebuild successful %-14s ${C_GREEN}[ OK ]${RESET}\n" ""
    fi
fi

# --- 2. Display Manager Cleanup ---
if [[ "$INSTALL_SDDM" == true || "$SETUP_SDDM_THEME" == true || "$REPLACE_DM" == true ]]; then
    echo -e "\n${C_CYAN}[ INFO ]${RESET} Configuring Display Manager..."
fi

if [[ "$REPLACE_DM" == true ]]; then
    DMS=("lightdm" "gdm" "gdm3" "lxdm" "lxdm-gtk3" "ly")
    for dm in "${DMS[@]}"; do
        if systemctl is-enabled "$dm.service" &>/dev/null || systemctl is-active "$dm.service" &>/dev/null; then
            echo "  -> Disabling conflicting Display Manager: $dm"
            sudo systemctl disable "$dm.service" 2>/dev/null || true
            sudo pacman -Rns --noconfirm "$dm" > /dev/null 2>&1 || true
        fi
    done
fi

if [[ "$INSTALL_SDDM" == true ]]; then
    sudo systemctl enable sddm.service -f
    printf "  -> SDDM enabled successfully %-14s ${C_GREEN}[ OK ]${RESET}\n" ""
fi

# --- 3. Repository Setup & Wallpapers ---
echo -e "\n${C_CYAN}[ INFO ]${RESET} Setting up dotfiles repository..."

OLD_COMMIT=""
NEW_COMMIT=""

# Use the local repo (where this script is) — we don't clone upstream's repo
if [ -f "$(pwd)/install.sh" ] && [ -d "$(pwd)/.config" ] && [ "$(pwd)" != "$HOME" ]; then
    REPO_DIR="$(pwd)"
    echo "  -> Using local repository at $REPO_DIR"
    if [ -d "$REPO_DIR/.git" ]; then
        NEW_COMMIT=$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null || echo "")
    fi
    OLD_COMMIT="$LAST_COMMIT"
else
    echo -e "${C_RED}[ ERR ] Run this script from the cloned repo directory.${RESET}"
    exit 1
fi

echo -e "\n${C_CYAN}[ INFO ]${RESET} Fetching wallpapers..."
mkdir -p "$WALLPAPER_DIR"

# Wallpaper source: ilyamiro/shell-wallpapers (upstream's curated collection).
# Lives at github.com/ilyamiro/shell-wallpapers, images under images/ subdir.
WALLPAPER_REPO_URL="https://github.com/ilyamiro/shell-wallpapers.git"
WALLPAPER_REPO_TMP="$(mktemp -d)/shell-wallpapers"

if [ -n "$(find "$WALLPAPER_DIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.webp' \) -print -quit 2>/dev/null)" ]; then
    echo -e "  -> ${C_GREEN}Wallpapers already present.${RESET} Skipping download."
elif [ -d "$REPO_DIR/wallpapers" ] && [ -n "$(ls -A "$REPO_DIR/wallpapers" 2>/dev/null)" ]; then
    # Local repo has wallpapers (e.g. someone vendored them) — use those
    cp -r "$REPO_DIR/wallpapers/"* "$WALLPAPER_DIR/" 2>/dev/null || true
    printf "  -> Wallpapers copied from local repo %-7s ${C_GREEN}[ OK ]${RESET}\n" ""
else
    # Clone ilyamiro/shell-wallpapers — depth 1 to avoid pulling full history
    echo "  -> Cloning $WALLPAPER_REPO_URL (depth 1)..."
    if git clone --depth 1 "$WALLPAPER_REPO_URL" "$WALLPAPER_REPO_TMP" >/dev/null 2>&1; then
        if [ ! -d "$WALLPAPER_REPO_TMP/images" ]; then
            printf "  -> Repo layout unexpected (no images/ dir) %-1s ${C_YELLOW}[WARN]${RESET}\n" ""
            echo "  -> Add wallpapers manually to $WALLPAPER_DIR"
        elif [ "$OPT_WALLPAPERS" = true ]; then
            # Full pack — copy everything from images/
            cp "$WALLPAPER_REPO_TMP/images/"*.{jpg,jpeg,png,gif,webp} "$WALLPAPER_DIR/" 2>/dev/null || true
            count=$(find "$WALLPAPER_DIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.jpeg' -o -iname '*.gif' -o -iname '*.webp' \) | wc -l)
            printf "  -> Copied full wallpaper pack (%d files) %-1s ${C_GREEN}[ OK ]${RESET}\n" "$count"
        else
            # 3 random — fast first install, you can grab more later
            mapfile -t _wps < <(find "$WALLPAPER_REPO_TMP/images" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.jpeg' -o -iname '*.gif' -o -iname '*.webp' \) | shuf -n 3)
            for w in "${_wps[@]}"; do
                cp "$w" "$WALLPAPER_DIR/" 2>/dev/null || true
            done
            printf "  -> Copied 3 random wallpapers %-13s ${C_GREEN}[ OK ]${RESET}\n" ""
            echo -e "  -> ${DIM}For the full pack: re-run with the menu option toggled,${RESET}"
            echo -e "  -> ${DIM}or git clone $WALLPAPER_REPO_URL manually.${RESET}"
        fi
        rm -rf "$(dirname "$WALLPAPER_REPO_TMP")"
    else
        printf "  -> Could not clone wallpaper repo %-13s ${C_YELLOW}[WARN]${RESET}\n" ""
        echo "  -> Network issue or repo moved. Add wallpapers manually to:"
        echo "  -> $WALLPAPER_DIR"
        echo "  -> Source: $WALLPAPER_REPO_URL"
    fi
fi

# --- 4. Copying Dotfiles & Backups ---
echo -e "\n${C_CYAN}[ INFO ]${RESET} Applying configurations & backing up old ones..."
TARGET_CONFIG_DIR="$HOME/.config"
BACKUP_DIR="$HOME/.config-backup-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

CONFIG_FOLDERS=("cava" "hypr" "kitty" "rofi" "matugen" "zsh" "swayosd")
[ "$INSTALL_NVIM" = true ] && CONFIG_FOLDERS+=("nvim")

mkdir -p "$TARGET_CONFIG_DIR"

for folder in "${CONFIG_FOLDERS[@]}"; do
    TARGET_PATH="$TARGET_CONFIG_DIR/$folder"
    SOURCE_PATH="$REPO_DIR/.config/$folder"

    if [ -d "$SOURCE_PATH" ]; then
        if [ -e "$TARGET_PATH" ] || [ -L "$TARGET_PATH" ]; then
            mv "$TARGET_PATH" "$BACKUP_DIR/$folder"
        fi
        cp -r "$SOURCE_PATH" "$TARGET_PATH"
        printf "  -> Copied %-31s ${C_GREEN}[ OK ]${RESET}\n" "$folder"
    fi
done

# Mark our scripts executable (bounded — only known dirs)
KNOWN_SCRIPT_DIRS=(
    "$TARGET_CONFIG_DIR/hypr/scripts"
    "$TARGET_CONFIG_DIR/hypr/scripts/quickshell"
)
for d in "${KNOWN_SCRIPT_DIRS[@]}"; do
    [ -d "$d" ] || continue
    find "$d" -maxdepth 1 -type f -name "*.sh" -exec chmod +x {} \;
done

# --- 4.5 Bake Hardware Variables into Template ---
if [ -f "$TARGET_CONFIG_DIR/hypr/templates/env.conf.template" ]; then
    echo "  -> Baking hardware environment variables into template..."
    if [ "$GPU_VENDOR" == "NVIDIA" ]; then
        NVIDIA_VARS="env = ELECTRON_OZONE_PLATFORM_HINT,auto\nenv = __NV_PRIME_RENDER_OFFLOAD,1\nenv = __GLX_VENDOR_LIBRARY_NAME,nvidia\nenv = LIBVA_DRIVER_NAME,nvidia"
        sed -i "s|{{HARDWARE_ENV}}|$NVIDIA_VARS|g" "$TARGET_CONFIG_DIR/hypr/templates/env.conf.template"
    else
        sed -i "s|{{HARDWARE_ENV}}||g" "$TARGET_CONFIG_DIR/hypr/templates/env.conf.template"
    fi
fi

# --- 4.6 Ensure Qt Wayland env vars are set (Quickshell crash fix) ---
# Without QT_QPA_PLATFORM=wayland, Qt may try the xcb plugin first, which crashes
# Quickshell on first launch in VMs and on systems missing libxcb-cursor.
# This block appends the needed env vars to env.conf if they aren't already there.
ENV_CONF="$TARGET_CONFIG_DIR/hypr/config/env.conf"
if [ -f "$ENV_CONF" ]; then
    if ! grep -q "QT_QPA_PLATFORM,wayland" "$ENV_CONF"; then
        echo "  -> Appending Qt Wayland env vars to env.conf..."
        cat >> "$ENV_CONF" <<'EOF'

# Qt Wayland enforcement (prevents Quickshell from trying xcb plugin)
env = QT_QPA_PLATFORM,wayland
env = QT_QPA_PLATFORMTHEME,qt6ct
env = QT_WAYLAND_DISABLE_WINDOWDECORATION,1
env = XDG_CURRENT_DESKTOP,Hyprland
env = XDG_SESSION_TYPE,wayland
env = XDG_SESSION_DESKTOP,Hyprland
env = GDK_BACKEND,wayland,x11
env = SDL_VIDEODRIVER,wayland
env = MOZ_ENABLE_WAYLAND,1
env = _JAVA_AWT_WM_NONREPARENTING,1
EOF
        printf "  -> Qt Wayland env vars appended %-19s ${C_GREEN}[ OK ]${RESET}\n" ""
    else
        printf "  -> Qt Wayland env vars already set %-17s ${C_GREEN}[ OK ]${RESET}\n" ""
    fi
fi


# ==============================================================================
# Settings.json (only if upstream's SSoT files exist)
# ==============================================================================
if [ -f "$REPO_DIR/.config/hypr/default_settings.json" ]; then
    echo -e "\n${C_CYAN}[ INFO ]${RESET} Establishing settings.json SSoT..."
    SETTINGS_FILE="$TARGET_CONFIG_DIR/hypr/settings.json"
    UPSTREAM_JSON="$REPO_DIR/.config/hypr/default_settings.json"
    mkdir -p "$(dirname "$SETTINGS_FILE")"

    if [ -f "$BACKUP_DIR/hypr/settings.json" ] && jq -e . "$BACKUP_DIR/hypr/settings.json" >/dev/null 2>&1; then
        OLD_JSON="$BACKUP_DIR/hypr/settings.json"
    else
        OLD_JSON="$UPSTREAM_JSON"
    fi

    jq -n --slurpfile local "$OLD_JSON" --slurpfile up "$UPSTREAM_JSON" \
       --arg langs "$KB_LAYOUTS" --arg wpdir "$WALLPAPER_DIR" --arg kbopt "$KB_OPTIONS" \
       --arg ovr_kb "$OPT_OVERRIDE_KEYBINDS" --arg ovr_su "$OPT_OVERRIDE_STARTUPS" '
       $up[0] as $u |
       (if ($local | length > 0) then $local[0] else $u end) as $l |
       ($u + $l) |
       .language = $langs | .wallpaperDir = $wpdir | .kbOptions = $kbopt |
       .keybinds = (if $ovr_kb == "true" then $u.keybinds else
           ($l.keybinds | map(((.mods // "") + "|" + (.key // "")))) as $local_keys |
           ($l.keybinds | map(.command)) as $local_cmds |
           ($u.keybinds | map(select(
               (((.mods // "") + "|" + (.key // "")) as $k | ($local_keys | index($k)) == null) and
               (.command as $cmd | ($local_cmds | index($cmd)) == null)
           ))) as $new_upstream |
           ($l.keybinds + $new_upstream)
       end) |
       .startup = (if $ovr_su == "true" then $u.startup else
           ($l.startup | map(.command)) as $local_startups |
           ($u.startup | map(select(.command as $cmd | ($local_startups | index($cmd)) == null))) as $new |
           ($l.startup + $new)
       end)
    ' > "$SETTINGS_FILE"

    printf "  -> settings.json built %-25s ${C_GREEN}[ OK ]${RESET}\n" ""
fi

# Weather Configuration
ENV_TARGET_DIR="$TARGET_CONFIG_DIR/hypr/scripts/quickshell/calendar"
OLD_ENV_IN_BACKUP="$BACKUP_DIR/hypr/scripts/quickshell/calendar/.env"

if [[ "$KEEP_OLD_ENV" == true ]] && [ -f "$OLD_ENV_IN_BACKUP" ]; then
    mkdir -p "$ENV_TARGET_DIR"
    cp "$OLD_ENV_IN_BACKUP" "$ENV_TARGET_DIR/.env"
    chmod 600 "$ENV_TARGET_DIR/.env"
    printf "  -> Restored Weather config %-21s ${C_GREEN}[ OK ]${RESET}\n" ""
elif [[ -n "$WEATHER_API_KEY" && "$WEATHER_API_KEY" != "Skipped" ]]; then
    mkdir -p "$ENV_TARGET_DIR"
    cat <<EOF > "$ENV_TARGET_DIR/.env"
OPENWEATHER_KEY=${WEATHER_API_KEY}
OPENWEATHER_CITY_ID=${WEATHER_CITY_ID}
OPENWEATHER_UNIT=${WEATHER_UNIT}
EOF
    chmod 600 "$ENV_TARGET_DIR/.env"
    printf "  -> Saved Weather config (mode 600) %-13s ${C_GREEN}[ OK ]${RESET}\n" ""
fi

# Restore Matugen colors
QS_COLORS_BACKUP="$BACKUP_DIR/hypr/scripts/quickshell/qs_colors.json"
QS_COLORS_TARGET="$TARGET_CONFIG_DIR/hypr/scripts/quickshell/qs_colors.json"
if [ -f "$QS_COLORS_BACKUP" ]; then
    mkdir -p "$(dirname "$QS_COLORS_TARGET")"
    cp "$QS_COLORS_BACKUP" "$QS_COLORS_TARGET"
    printf "  -> Restored Quickshell colors %-17s ${C_GREEN}[ OK ]${RESET}\n" ""
fi

# Patch WallpaperPicker.qml
WP_QML="$TARGET_CONFIG_DIR/hypr/scripts/quickshell/wallpaper/WallpaperPicker.qml"
if [ -f "$WP_QML" ]; then
    sed -i 's/ \+--source-color-index 0//g' "$WP_QML"
    sed -i 's/matugen image "[^"]*"/& --source-color-index 0/g' "$WP_QML"
fi

if [ -d "$TARGET_CONFIG_DIR/hypr/scripts" ]; then
    find "$TARGET_CONFIG_DIR/hypr/scripts" -type f -exec sed -i -e 's/swww-daemon/awww-daemon/g' -e 's/swww/awww/g' {} +
fi

# Zsh Dynamism
ZSH_RC="$HOME/.zshrc"
if [ -f "$ZSH_RC" ]; then
    sed -i '/# Dynamic System Paths/d' "$ZSH_RC"
    sed -i '/export WALLPAPER_DIR=/d' "$ZSH_RC"
    sed -i '/export SCRIPT_DIR=/d' "$ZSH_RC"
    echo -e "\n# Dynamic System Paths" >> "$ZSH_RC"
    echo "export WALLPAPER_DIR=\"$WALLPAPER_DIR\"" >> "$ZSH_RC"
    echo "export SCRIPT_DIR=\"$HOME/.config/hypr/scripts\"" >> "$ZSH_RC"
    sed -i "s/OS_LOGO_PLACEHOLDER/${OS}_small/g" "$ZSH_RC"
fi

# --- 6.5 GTK and Qt Theming ---
echo -e "\n${C_CYAN}[ INFO ]${RESET} Configuring GTK and Qt theming..."
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark' 2>/dev/null || true

mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"
echo '@import url("file://'"$HOME"'/.cache/matugen/colors-gtk.css");' > "$HOME/.config/gtk-3.0/gtk.css"
echo '@import url("file://'"$HOME"'/.cache/matugen/colors-gtk.css");' > "$HOME/.config/gtk-4.0/gtk.css"

cat <<EOF > "$HOME/.config/gtk-3.0/settings.ini"
[Settings]
gtk-application-prefer-dark-theme=1
gtk-theme-name=adw-gtk3-dark
EOF
cat <<EOF > "$HOME/.config/gtk-4.0/settings.ini"
[Settings]
gtk-application-prefer-dark-theme=1
EOF

mkdir -p "$HOME/.config/qt5ct/colors" "$HOME/.config/qt5ct/qss"
mkdir -p "$HOME/.config/qt6ct/colors" "$HOME/.config/qt6ct/qss"

cat <<EOF > "$HOME/.config/qt5ct/qt5ct.conf"
[Appearance]
color_scheme_path=$HOME/.config/qt5ct/colors/matugen.conf
custom_palette=true
standard_dialogs=default
style=Fusion
stylesheets=$HOME/.config/qt5ct/qss/matugen-style.qss

[Interface]
stylesheets=$HOME/.config/qt5ct/qss/matugen-style.qss
EOF

cat <<EOF > "$HOME/.config/qt6ct/qt6ct.conf"
[Appearance]
color_scheme_path=$HOME/.config/qt6ct/colors/matugen.conf
custom_palette=true
standard_dialogs=default
style=Fusion
stylesheets=$HOME/.config/qt6ct/qss/matugen-style.qss

[Interface]
stylesheets=$HOME/.config/qt6ct/qss/matugen-style.qss
EOF

printf "  -> Matugen GTK & Qt initialized %-18s ${C_GREEN}[ OK ]${RESET}\n" ""

# Cava wrapper
mkdir -p "$HOME/.local/bin"
if [ -f "$REPO_DIR/utils/bin/cava" ]; then
    cp "$REPO_DIR/utils/bin/cava" "$HOME/.local/bin/cava"
    chmod +x "$HOME/.local/bin/cava"
    printf "  -> Deployed Cava wrapper %-23s ${C_GREEN}[ OK ]${RESET}\n" ""
fi

# ==============================================================================
# AI STACK: Ollama → LiteLLM → Hermes (NEW vs upstream)
# ==============================================================================
LITELLM_KEY=""

if [ "$OPT_AI" = true ]; then
    # Generate autobrowse auth token early so Hermes config can reference it.
    # If a previous install set one in the version state file, reuse it.
    if [ -z "${AUTOBROWSE_AUTH_TOKEN:-}" ]; then
        AUTOBROWSE_AUTH_TOKEN="$(openssl rand -hex 24)"
    fi
    # ─── 6.6 Ollama ────────────────────────────────────────────────────────
    echo -e "\n${C_CYAN}[ INFO ]${RESET} Setting up Ollama (local model server)..."

    if command -v ollama &>/dev/null; then
        # Lock Ollama to localhost (default binds 0.0.0.0:11434).
        # Override via systemd drop-in so package updates don't clobber it.
        sudo mkdir -p /etc/systemd/system/ollama.service.d
        sudo tee /etc/systemd/system/ollama.service.d/override.conf >/dev/null <<'OLLAMAEOF'
[Service]
Environment=OLLAMA_HOST=127.0.0.1:11434
OLLAMAEOF
        sudo systemctl daemon-reload

        if sudo systemctl enable --now ollama 2>/dev/null; then
            printf "  -> ollama.service running (localhost only) %-4s ${C_GREEN}[ OK ]${RESET}\n" ""
        else
            printf "  -> ollama.service failed %-22s ${C_YELLOW}[WARN]${RESET}\n" ""
        fi

        for i in $(seq 1 10); do
            if curl -fsS -m 1 http://localhost:11434/api/tags &>/dev/null; then
                printf "  -> Ollama responding %-26s ${C_GREEN}[ OK ]${RESET}\n" ""
                break
            fi
            sleep 1
        done
        echo -e "  -> ${C_CYAN}Pull a model with:${RESET} ${BOLD}ollama pull qwen2.5:7b${RESET}"
    else
        printf "  -> ollama not installed %-23s ${C_YELLOW}[WARN]${RESET}\n" ""
    fi

    # ─── 6.7 LiteLLM ───────────────────────────────────────────────────────
    echo -e "\n${C_CYAN}[ INFO ]${RESET} Setting up LiteLLM router..."

    LITELLM_VENV="$HOME/.local/share/litellm-venv"
    LITELLM_CONFIG="$HOME/.config/litellm/config.yaml"
    LITELLM_SERVICE="$HOME/.config/systemd/user/litellm.service"

    # LiteLLM proxy (uvloop/fastuuid/orjson) doesn't build cleanly on Python 3.13+.
    # Pick the highest available Python <= 3.12 for the venv.
    LITELLM_PY=""
    for cand in python3.12 python3.11 python3.10; do
        if command -v "$cand" &>/dev/null; then
            LITELLM_PY="$cand"
            break
        fi
    done
    if [ -z "$LITELLM_PY" ]; then
        printf "  -> No Python 3.12/3.11/3.10 found %-15s ${C_RED}[FAIL]${RESET}\n" ""
        printf "  -> Install with: ${BOLD}paru -S python312${RESET}\n"
        FAILED_PKGS+=("litellm[proxy]")
    else
        printf "  -> Using interpreter: %-25s ${C_GREEN}[ OK ]${RESET}\n" "$LITELLM_PY"

        if [ ! -d "$LITELLM_VENV" ]; then
            "$LITELLM_PY" -m venv "$LITELLM_VENV"
        else
            # If existing venv was built with a now-removed Python (e.g. 3.13 → 3.12 switch),
            # the symlinks break. Recreate if the embedded python is gone.
            if ! "$LITELLM_VENV/bin/python" --version &>/dev/null; then
                printf "  -> Existing venv broken — recreating %-9s ${C_YELLOW}[WARN]${RESET}\n" ""
                rm -rf "$LITELLM_VENV"
                "$LITELLM_PY" -m venv "$LITELLM_VENV"
            fi
        fi
        "$LITELLM_VENV/bin/pip" install --upgrade pip --quiet 2>&1 | tail -1 || true

        if "$LITELLM_VENV/bin/pip" install --quiet "litellm[proxy]"; then
            printf "  -> LiteLLM installed %-26s ${C_GREEN}[ OK ]${RESET}\n" ""
        else
            printf "  -> LiteLLM install failed %-21s ${C_RED}[FAIL]${RESET}\n" ""
            FAILED_PKGS+=("litellm[proxy]")
        fi
    fi

    mkdir -p "$(dirname "$LITELLM_CONFIG")"
    if [ -f "$LITELLM_CONFIG" ]; then
        chmod 600 "$LITELLM_CONFIG"
        LITELLM_KEY=$(grep "^  master_key:" "$LITELLM_CONFIG" | awk '{print $2}')
        printf "  -> LiteLLM config exists (key preserved) %-7s ${C_GREEN}[ OK ]${RESET}\n" ""
    else
        LITELLM_KEY="sk-$(openssl rand -hex 24)"
        cat > "$LITELLM_CONFIG" <<YAML
# LiteLLM router. Edit and run: systemctl --user restart litellm
model_list:
  - model_name: local
    litellm_params:
      model: ollama/qwen2.5:7b
      api_base: http://localhost:11434

  - model_name: vision
    litellm_params:
      model: ollama/qwen2.5-vl:7b
      api_base: http://localhost:11434

  # Uncomment + add your Ollama Cloud key:
  # - model_name: deep-think
  #   litellm_params:
  #     model: openai/qwen3.5:cloud
  #     api_base: https://ollama.com/v1
  #     api_key: os.environ/OLLAMA_CLOUD_API_KEY

general_settings:
  master_key: $LITELLM_KEY
  database_url: "sqlite:///$HOME/.local/share/litellm.db"

litellm_settings:
  drop_params: true
  json_logs: true
  request_timeout: 600
  num_retries: 2
YAML
        chmod 600 "$LITELLM_CONFIG"
        printf "  -> LiteLLM config written (mode 600) %-11s ${C_GREEN}[ OK ]${RESET}\n" ""
    fi

    mkdir -p "$(dirname "$LITELLM_SERVICE")"
    cat > "$LITELLM_SERVICE" <<EOF
[Unit]
Description=LiteLLM router
After=network-online.target

[Service]
Type=simple
ExecStart=$LITELLM_VENV/bin/litellm --config $LITELLM_CONFIG --port 4000 --host 127.0.0.1
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF
    chmod 644 "$LITELLM_SERVICE"
    systemctl --user daemon-reload

    if systemctl --user enable --now litellm.service 2>/dev/null; then
        printf "  -> litellm.service enabled %-20s ${C_GREEN}[ OK ]${RESET}\n" ""
    else
        printf "  -> litellm.service failed %-21s ${C_YELLOW}[WARN]${RESET}\n" ""
    fi

    if ! loginctl show-user "$USER" 2>/dev/null | grep -q "Linger=yes"; then
        sudo loginctl enable-linger "$USER" 2>/dev/null && \
            printf "  -> User lingering enabled %-21s ${C_GREEN}[ OK ]${RESET}\n" "" || true
    fi

    for i in $(seq 1 15); do
        if curl -fsS -m 2 "http://localhost:4000/health/readiness" \
            -H "Authorization: Bearer $LITELLM_KEY" &>/dev/null; then
            printf "  -> LiteLLM health check %-23s ${C_GREEN}[ OK ]${RESET}\n" ""
            break
        fi
        sleep 1
    done

    # ─── 6.8 Hermes Agent ──────────────────────────────────────────────────
    #
    # Hermes Agent (NousResearch) install rewritten for current upstream:
    #
    #   - Uses the official installer with --skip-setup (we provide our own config).
    #   - No more Playwright/Chromium download — current Hermes only does
    #     `npm install` for browser tools, and only USES them when invoked.
    #     Nothing to patch out. The old sed patch and `HERMES_SKIP_BROWSER` env
    #     vars are gone.
    #   - Config layout matches current upstream:
    #       ~/.hermes/config.yaml   (inference + provider config)
    #       ~/.hermes/.env          (LITELLM_API_KEY for the custom provider)
    #       ~/.hermes/SOUL.md       (persona — leave installer to create)
    #   - LiteLLM is registered as a custom_provider; Hermes accepts any
    #     OpenAI-compatible endpoint via that mechanism.
    #   - autobrowse MCP server is added via `hermes mcp add` AFTER install,
    #     not by hand-writing YAML, because Hermes's MCP schema is internal.
    #
    # If the user has no internet or doesn't consent, we skip cleanly.
    # ────────────────────────────────────────────────────────────────────────
    echo -e "\n${C_CYAN}[ INFO ]${RESET} Setting up Hermes Agent..."

    echo -e "\n${C_CYAN}[ INFO ]${RESET} Setting up Hermes Agent..."

    HERMES_HOME="$HOME/.hermes"
    HERMES_CFG="$HERMES_HOME/config.yaml"
    HERMES_ENV="$HERMES_HOME/.env"
    HERMES_INSTALL_URL="https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh"

    if command -v hermes &>/dev/null; then
        printf "  -> hermes already installed %-19s ${C_GREEN}[ OK ]${RESET}\n" ""
    elif [ "$HEADLESS" = "true" ]; then
        printf "  -> Hermes (skipped in headless mode) %-10s ${C_BLUE}[SKIP]${RESET}\n" ""
    else
        echo -e "  -> ${C_YELLOW}Hermes is third-party (NousResearch).${RESET}"
        echo -e "  -> ${DIM}Installer: $HERMES_INSTALL_URL${RESET}"
        echo -e "  -> ${DIM}Will run with --skip-setup; we provide config separately.${RESET}"
        read -rp "  Install Hermes Agent now? [y/N] " yn
        if [[ "$yn" =~ ^[Yy]$ ]]; then
            tmp_inst=$(mktemp --suffix=.sh)
            if curl -fsSL "$HERMES_INSTALL_URL" -o "$tmp_inst"; then
                echo -e "  -> Saved installer to $tmp_inst"
                echo -e "  -> SHA-256: $(sha256sum "$tmp_inst" | awk '{print $1}')"
                echo -e "  -> ${DIM}Review with: less $tmp_inst${RESET}"
                read -rp "  Proceed with installation? [y/N] " yn2
                if [[ "$yn2" =~ ^[Yy]$ ]]; then
                    # --skip-setup avoids the interactive provider wizard at end
                    # of install — we write our own config.yaml below.
                    if sudo bash "$tmp_inst" --skip-setup; then
                        printf "  -> Hermes installed %-27s ${C_GREEN}[ OK ]${RESET}\n" ""
                    else
                        printf "  -> Hermes installer non-zero exit %-13s ${C_YELLOW}[WARN]${RESET}\n" ""
                    fi
                else
                    echo "  -> Skipped (you can run later: sudo bash $tmp_inst --skip-setup)"
                fi
            else
                printf "  -> Could not fetch installer %-21s ${C_YELLOW}[WARN]${RESET}\n" ""
            fi
            rm -f "$tmp_inst"
        else
            echo "  -> Skipped Hermes install"
        fi
    fi

    # ─── Hermes configuration ───────────────────────────────────────────────
    # Always (re)write ~/.hermes/.env and ~/.hermes/config.yaml when Hermes is
    # installed, even if the install was skipped above — the user may have
    # installed Hermes themselves and just wants our wiring.

    if command -v hermes &>/dev/null; then
        mkdir -p "$HERMES_HOME"
        chmod 700 "$HERMES_HOME"

        # ── .env: API keys live here, kept out of YAML for security ──
        # Hermes loads ~/.hermes/.env automatically at startup. We point at
        # LiteLLM as the unified gateway; LiteLLM does its own routing to
        # Ollama / cloud providers based on the model name.
        if [ ! -f "$HERMES_ENV" ]; then
            cat > "$HERMES_ENV" <<ENVEOF
# Hermes environment — auto-generated by install.sh.
# Keep API keys here, NOT in config.yaml.

# LiteLLM gateway — running on this host at port 4000.
# Hermes treats this as a "custom" OpenAI-compatible provider.
LITELLM_API_KEY=${LITELLM_KEY:-changeme}
LITELLM_BASE_URL=http://localhost:4000

# Optional cloud fallbacks. Leave commented unless you actually have keys.
# OPENROUTER_API_KEY=
# ANTHROPIC_API_KEY=
# OPENAI_API_KEY=
ENVEOF
            chmod 600 "$HERMES_ENV"
            printf "  -> Wrote ~/.hermes/.env (mode 600) %-12s ${C_GREEN}[ OK ]${RESET}\n" ""
        else
            printf "  -> ~/.hermes/.env already exists, keeping it %-1s ${C_BLUE}[KEEP]${RESET}\n" ""
        fi

        # ── config.yaml: Hermes's main config ──
        # Schema reference: cli-config.yaml.example in the Hermes repo.
        # We register LiteLLM as a named custom provider, then point
        # `inference` at it. If LiteLLM isn't running, Hermes will error at
        # runtime with a clear message — the YAML itself is always valid.
        if [ ! -f "$HERMES_CFG" ]; then
            # Pick a primary model name. If user has a local LiteLLM route
            # named "local" (our default), use that; otherwise default to a
            # raw Ollama model name and let LiteLLM pass-through route it.
            H_MODEL="local"
            [ -z "$LITELLM_KEY" ] && H_MODEL="qwen2.5:7b"

            cat > "$HERMES_CFG" <<YAMLEOF
# Hermes Agent configuration — auto-generated by install.sh.
# This file is YAML. Keep API keys in ~/.hermes/.env, NOT here.
# To regenerate: delete this file and re-run install.sh.

# ── Inference ────────────────────────────────────────────────────────────
# Use our LiteLLM gateway as a named custom provider.
inference:
  provider: litellm-local
  model: ${H_MODEL}

# ── Custom providers ─────────────────────────────────────────────────────
# LiteLLM exposes an OpenAI-compatible API at :4000.
# api_key resolves from the LITELLM_API_KEY env var (set in ~/.hermes/.env).
custom_providers:
  - name: litellm-local
    base_url: http://localhost:4000
    api_key_env: LITELLM_API_KEY
    # Tag this provider so Hermes knows it speaks OpenAI's chat format.
    api_format: openai

# ── Terminal tool ────────────────────────────────────────────────────────
# Hermes can run shell commands. Default to ASK approval before every run.
# Edit allowlist/denylist as desired; these are starting points only.
terminal:
  backend: local
  approval: ask
  allowlist:
    - ls
    - cat
    - pwd
    - echo
    - hyprctl monitors
    - hyprctl clients
  denylist:
    - rm -rf
    - sudo
    - dd
    - mkfs
    - passwd
    - chmod 777
    - chown root
    - ":(){"

# ── Display ──────────────────────────────────────────────────────────────
display:
  tool_progress: new
YAMLEOF
            chmod 600 "$HERMES_CFG"
            printf "  -> Wrote ~/.hermes/config.yaml (mode 600) %-3s ${C_GREEN}[ OK ]${RESET}\n" ""
        else
            printf "  -> ~/.hermes/config.yaml already exists %-7s ${C_BLUE}[KEEP]${RESET}\n" ""
        fi

        # ── MCP server registration: autobrowse ──
        # Configure via the `hermes mcp` CLI rather than hand-editing YAML.
        # The MCP schema is owned by Hermes and changes; the CLI is stable.
        # We register only if autobrowse appears to be running locally.
        if [ -n "${AUTOBROWSE_AUTH_TOKEN:-}" ] && command -v hermes &>/dev/null; then
            # Use `hermes mcp list` to detect prior registration. Hermes
            # returns non-zero if mcp isn't configured at all — in that case
            # we just try the add. Either way, errors are non-fatal.
            if ! hermes mcp list 2>/dev/null | grep -qE '\bautobrowse\b'; then
                if hermes mcp add autobrowse \
                        --transport http \
                        --url "http://localhost:8080/mcp/" \
                        --header "Authorization: Bearer ${AUTOBROWSE_AUTH_TOKEN}" \
                        2>/dev/null; then
                    printf "  -> Registered MCP server: autobrowse %-9s ${C_GREEN}[ OK ]${RESET}\n" ""
                else
                    printf "  -> MCP autobrowse register failed %-13s ${C_YELLOW}[WARN]${RESET}\n" ""
                    echo "  -> Add manually later:"
                    echo "       hermes mcp add autobrowse --transport http \\"
                    echo "         --url http://localhost:8080/mcp/ \\"
                    echo "         --header 'Authorization: Bearer <token>'"
                fi
            else
                printf "  -> MCP autobrowse already registered %-10s ${C_BLUE}[KEEP]${RESET}\n" ""
            fi
        fi

        # ── Convenience: ensure ~/.local/bin is on PATH for this shell ──
        # The installer adds it to .bashrc/.zshrc, but our current shell
        # session won't pick that up. Tell the user.
        if ! echo "$PATH" | tr ':' '\n' | grep -qx "$HOME/.local/bin"; then
            echo -e "  -> ${DIM}Note: ~/.local/bin not on PATH in this shell.${RESET}"
            echo -e "  -> ${DIM}Restart your terminal or run: source ~/.zshrc${RESET}"
        fi
    fi

    # ─── 6.85 Kavita (reading server, runs in podman locally) ─────────────
    echo -e "\n${C_CYAN}[ INFO ]${RESET} Setting up Kavita reading server..."

    KAVITA_QUADLET_DIR="$HOME/.config/containers/systemd"
    KAVITA_QUADLET="$KAVITA_QUADLET_DIR/kavita.container"
    KAVITA_LIBRARY="$HOME/Books"

    mkdir -p "$KAVITA_QUADLET_DIR" "$KAVITA_LIBRARY"

    # Pull the image up front so the first start isn't slow + fails quietly
    if command -v podman &>/dev/null; then
        echo "  -> Pulling Kavita image (jvmilazz0/kavita:latest)..."
        if podman pull docker.io/jvmilazz0/kavita:latest 2>&1 | tail -3; then
            printf "  -> Kavita image pulled %-25s ${C_GREEN}[ OK ]${RESET}\n" ""
        else
            printf "  -> Kavita image pull failed %-20s ${C_YELLOW}[WARN]${RESET}\n" ""
        fi
    else
        printf "  -> podman not installed %-23s ${C_YELLOW}[WARN]${RESET}\n" ""
    fi

    # Write the quadlet — systemd-podman will compile it to a service unit
    cat > "$KAVITA_QUADLET" <<EOF
[Unit]
Description=Kavita reading server
After=network-online.target

[Container]
Image=docker.io/jvmilazz0/kavita:latest
ContainerName=kavita
PublishPort=127.0.0.1:5000:5000
Environment=TZ=$(cat /etc/timezone 2>/dev/null || echo "America/Los_Angeles")
Volume=kavita-config:/kavita/config
Volume=$KAVITA_LIBRARY:/library:Z
AutoUpdate=registry

[Service]
Restart=always
TimeoutStartSec=120

[Install]
WantedBy=default.target
EOF
    chmod 644 "$KAVITA_QUADLET"
    printf "  -> Kavita quadlet written %-21s ${C_GREEN}[ OK ]${RESET}\n" ""

    # Reload + enable
    systemctl --user daemon-reload
    if systemctl --user enable --now kavita.service 2>/dev/null; then
        printf "  -> kavita.service enabled %-21s ${C_GREEN}[ OK ]${RESET}\n" ""
    else
        printf "  -> kavita.service failed %-22s ${C_YELLOW}[WARN]${RESET}\n" ""
        printf "  -> ${DIM}Check: journalctl --user -xeu kavita${RESET}\n"
    fi

    # Wait briefly for Kavita to come up — first-time DB init can take 30s+
    echo "  -> Waiting for Kavita web UI..."
    for i in $(seq 1 20); do
        if curl -fsS -m 1 http://localhost:5000 >/dev/null 2>&1; then
            printf "  -> Kavita responding at localhost:5000 %-7s ${C_GREEN}[ OK ]${RESET}\n" ""
            break
        fi
        sleep 1
        [ "$i" -eq 20 ] && printf "  -> Kavita slow to start (still pending) %-6s ${C_YELLOW}[WARN]${RESET}\n" ""
    done

    echo "  -> ${C_CYAN}First-time setup:${RESET} Open ${BOLD}http://localhost:5000${RESET}"
    echo "  -> ${C_CYAN}Library path:${RESET} $KAVITA_LIBRARY (drop books here, mounted as /library inside)"
    echo "  -> ${C_CYAN}Get API key:${RESET} Account → API Key → paste into ai_config.json"

    # ─── 6.87 stealthy-auto-browse (replaces Hermes built-in Chromium browser) ──
    echo -e "\n${C_CYAN}[ INFO ]${RESET} Setting up stealthy-auto-browse (browser backend for Hermes)..."

    AUTOBROWSE_QUADLET="$HOME/.config/containers/systemd/autobrowse.container"
    # AUTOBROWSE_AUTH_TOKEN was generated earlier in the OPT_AI block

    if command -v podman &>/dev/null; then
        echo "  -> Pulling stealthy-auto-browse image (psyb0t/stealthy-auto-browse:latest)..."
        if podman pull docker.io/psyb0t/stealthy-auto-browse:latest 2>&1 | tail -3; then
            printf "  -> autobrowse image pulled %-20s ${C_GREEN}[ OK ]${RESET}\n" ""
        else
            printf "  -> autobrowse image pull failed %-15s ${C_YELLOW}[WARN]${RESET}\n" ""
        fi
    fi

    cat > "$AUTOBROWSE_QUADLET" <<EOF
[Unit]
Description=stealthy-auto-browse (Camoufox stealth browser, MCP server for Hermes)
After=network-online.target

[Container]
Image=docker.io/psyb0t/stealthy-auto-browse:latest
ContainerName=autobrowse
# Port 8080 = JSON HTTP API + MCP server at /mcp
# Port 5900 = noVNC viewer for live debugging
# Bound to 127.0.0.1 only — Hermes talks to it from the same machine.
PublishPort=127.0.0.1:8080:8080
PublishPort=127.0.0.1:5900:5900
Environment=TZ=$(cat /etc/timezone 2>/dev/null || echo "America/Los_Angeles")
Environment=AUTH_TOKEN=$AUTOBROWSE_AUTH_TOKEN
# Persistent browser profile (cookies, extensions, history)
Volume=autobrowse-profile:/userdata
AutoUpdate=registry

[Service]
Restart=always
TimeoutStartSec=180

[Install]
WantedBy=default.target
EOF
    chmod 644 "$AUTOBROWSE_QUADLET"
    printf "  -> autobrowse quadlet written %-17s ${C_GREEN}[ OK ]${RESET}\n" ""

    systemctl --user daemon-reload
    if systemctl --user enable --now autobrowse.service 2>/dev/null; then
        printf "  -> autobrowse.service enabled %-17s ${C_GREEN}[ OK ]${RESET}\n" ""
    else
        printf "  -> autobrowse.service failed %-18s ${C_YELLOW}[WARN]${RESET}\n" ""
        printf "  -> ${DIM}Check: journalctl --user -xeu autobrowse${RESET}\n"
    fi

    # Wait for the MCP endpoint to come up
    echo "  -> Waiting for autobrowse MCP endpoint..."
    for i in $(seq 1 30); do
        if curl -fsS -m 1 http://localhost:8080/ -H "Authorization: Bearer $AUTOBROWSE_AUTH_TOKEN" >/dev/null 2>&1; then
            printf "  -> autobrowse responding at :8080 %-13s ${C_GREEN}[ OK ]${RESET}\n" ""
            break
        fi
        sleep 1
        [ "$i" -eq 30 ] && printf "  -> autobrowse slow to start %-19s ${C_YELLOW}[WARN]${RESET}\n" ""
    done

    echo "  -> ${C_CYAN}MCP endpoint:${RESET} http://localhost:8080/mcp/"
    echo "  -> ${C_CYAN}Live VNC:${RESET}    http://localhost:5900/  (watch the browser in real time)"
    echo "  -> ${C_CYAN}Auth token:${RESET}  saved to version state file (for Hermes wiring)"

    # ─── 6.9 AI popup config ───────────────────────────────────────────────
    AI_CFG="$HOME/.config/hypr/ai_config.json"
    if [ ! -f "$AI_CFG" ]; then
        mkdir -p "$(dirname "$AI_CFG")"
        cat > "$AI_CFG" <<JSON
{
    "api_key": "${LITELLM_KEY:-PASTE_LITELLM_KEY_HERE}",
    "model": "local",
    "base_url": "http://localhost:4000",
    "lichess_token": "",
    "kavita_url": "http://localhost:5000",
    "kavita_api_key": "",
    "hermes_enabled": true,
    "hermes_endpoint": "http://localhost:5400/api/agent",
    "hermes_token": "",
    "approval_policy": "ask"
}
JSON
        chmod 600 "$AI_CFG"
        printf "  -> AI popup config written (mode 600) %-9s ${C_GREEN}[ OK ]${RESET}\n" ""
    else
        chmod 600 "$AI_CFG" 2>/dev/null || true
        printf "  -> AI popup config exists (untouched) %-9s ${C_GREEN}[ OK ]${RESET}\n" ""
    fi
fi
# ──────────────────────────────────────────────────────────────────────────

# Pipewire / OS services
sudo systemctl --global enable pipewire wireplumber pipewire-pulse 2>/dev/null || true
systemctl --user start pipewire wireplumber pipewire-pulse 2>/dev/null || true

sudo systemctl enable --now swayosd-libinput-backend.service 2>/dev/null || true
printf "  -> SwayOSD libinput backend enabled %-12s ${C_GREEN}[ OK ]${RESET}\n" ""

if [ -f "$HOME/.config/systemd/user/easyeffects.service" ]; then
    systemctl --user stop easyeffects.service 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/easyeffects.service"
    systemctl --user daemon-reload 2>/dev/null || true
fi
systemctl --user enable easyeffects.service 2>/dev/null || true

if [ "$INSTALL_ZSH" = true ] && command -v zsh &> /dev/null; then
    if [ -f "$HOME/.zshrc" ]; then
        mkdir -p "$TARGET_CONFIG_DIR/zsh"
        grep "^alias " "$HOME/.zshrc" > "$TARGET_CONFIG_DIR/zsh/user_aliases.zsh" || true
        [ -s "$TARGET_CONFIG_DIR/zsh/user_aliases.zsh" ] || rm -f "$TARGET_CONFIG_DIR/zsh/user_aliases.zsh"
    fi
    cp "$TARGET_CONFIG_DIR/zsh/.zshrc" "$HOME/.zshrc" 2>/dev/null || true
    chsh -s $(which zsh) "$USER"
    if [ -f "$TARGET_CONFIG_DIR/zsh/user_aliases.zsh" ]; then
        sed -i '/# Load User Aliases/d' "$HOME/.zshrc"
        echo -e "\n# Load User Aliases" >> "$HOME/.zshrc"
        echo "source $TARGET_CONFIG_DIR/zsh/user_aliases.zsh" >> "$HOME/.zshrc"
    fi
    printf "  -> Zsh set as default shell %-19s ${C_GREEN}[ OK ]${RESET}\n" ""
fi

# --- 5. Fonts ---
echo -e "\n${C_CYAN}[ INFO ]${RESET} Installing fonts..."
TARGET_FONTS_DIR="$HOME/.local/share/fonts"
REPO_FONTS_DIR="$REPO_DIR/.local/share/fonts"
mkdir -p "$TARGET_FONTS_DIR"

if [ -d "$REPO_FONTS_DIR" ]; then
    cp -r "$REPO_FONTS_DIR/"* "$TARGET_FONTS_DIR/" 2>/dev/null || true
fi

if [ -d "$TARGET_FONTS_DIR/IosevkaNerdFont" ] && [ "$(ls -A "$TARGET_FONTS_DIR/IosevkaNerdFont" 2>/dev/null | grep -i "\.ttf")" ]; then
    echo -e "  -> ${C_GREEN}Iosevka already installed.${RESET}"
else
    mkdir -p /tmp/iosevka-pack
    curl -fLo /tmp/iosevka-pack/Iosevka.zip https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Iosevka.zip
    unzip -q /tmp/iosevka-pack/Iosevka.zip -d /tmp/iosevka-pack/
    mkdir -p "$TARGET_FONTS_DIR/IosevkaNerdFont"
    mv /tmp/iosevka-pack/*.ttf "$TARGET_FONTS_DIR/IosevkaNerdFont/"
    sudo cp -r "$TARGET_FONTS_DIR/IosevkaNerdFont" /usr/share/fonts/
    rm -rf /tmp/iosevka-pack
    rm -f "$TARGET_FONTS_DIR/IosevkaNerdFont/"*Mono*.ttf
fi

find "$TARGET_FONTS_DIR" -type f -exec chmod 644 {} \; 2>/dev/null
find "$TARGET_FONTS_DIR" -type d -exec chmod 755 {} \; 2>/dev/null

if command -v fc-cache &> /dev/null; then
    fc-cache -f "$TARGET_FONTS_DIR" > /dev/null 2>&1
    printf "  -> Font cache updated %-25s ${C_GREEN}[ OK ]${RESET}\n" ""
fi

# Battery vs Desktop
QS_BAT_DIR="$TARGET_CONFIG_DIR/hypr/scripts/quickshell/battery"
REPO_BAT_DIR="$REPO_DIR/.config/hypr/scripts/quickshell/battery"
echo -e "\n${C_CYAN}[ INFO ]${RESET} Detecting chassis..."
if ls /sys/class/power_supply/BAT* 1> /dev/null 2>&1; then
    echo -e "  -> ${C_GREEN}Battery detected.${RESET} Using laptop widget."
    [ -f "$REPO_BAT_DIR/BatteryPopup.qml" ] && cp -f "$REPO_BAT_DIR/BatteryPopup.qml" "$QS_BAT_DIR/BatteryPopup.qml" 2>/dev/null || true
else
    echo -e "  -> ${C_YELLOW}No battery (Desktop).${RESET}"
    [ -f "$REPO_BAT_DIR/BatteryPopupAlt.qml" ] && cp -f "$REPO_BAT_DIR/BatteryPopupAlt.qml" "$QS_BAT_DIR/BatteryPopup.qml" 2>/dev/null || true
fi

echo -e "\n${C_CYAN}[ INFO ]${RESET} Enabling core services..."
sudo systemctl enable NetworkManager.service
printf "  -> NetworkManager enabled %-23s ${C_GREEN}[ OK ]${RESET}\n" ""
sudo systemctl enable --now power-profiles-daemon.service 2>/dev/null || true
printf "  -> Power Profiles Daemon enabled %-13s ${C_GREEN}[ OK ]${RESET}\n" ""
sudo systemctl enable --now bluetooth.service 2>/dev/null || true
printf "  -> Bluetooth enabled %-29s ${C_GREEN}[ OK ]${RESET}\n" ""

# ==============================================================================
# SDDM Astronaut theme (replaces upstream's matugen-minimal SDDM theme)
# ==============================================================================
if [[ "$SETUP_SDDM_THEME" == true ]]; then
    echo -e "\n${C_CYAN}[ INFO ]${RESET} Installing SDDM Astronaut theme..."

    THEME_DIR="/usr/share/sddm/themes/sddm-astronaut-theme"
    THEME_VARIANT="astronaut"
    THEME_REPO="https://github.com/Keyitdev/sddm-astronaut-theme.git"

    if [ -d "$THEME_DIR" ]; then
        sudo git -C "$THEME_DIR" fetch --quiet origin master 2>/dev/null || true
        sudo git -C "$THEME_DIR" reset --hard origin/master 2>/dev/null || true
        printf "  -> Astronaut theme updated %-19s ${C_GREEN}[ OK ]${RESET}\n" ""
    else
        if sudo git clone --depth 1 -b master "$THEME_REPO" "$THEME_DIR" 2>&1 | tail -2; then
            printf "  -> Astronaut theme cloned %-21s ${C_GREEN}[ OK ]${RESET}\n" ""
        else
            printf "  -> Astronaut clone failed %-21s ${C_YELLOW}[WARN]${RESET}\n" ""
        fi
    fi

    if [ -d "$THEME_DIR/Fonts" ]; then
        sudo cp -rn "$THEME_DIR/Fonts/"* /usr/share/fonts/ 2>/dev/null || true
        sudo fc-cache -f /usr/share/fonts >/dev/null
    fi

    # Variant selection — fall back to first available if requested doesn't exist
    if [ -f "$THEME_DIR/Themes/${THEME_VARIANT}.conf" ]; then
        sudo sed -i "s|^ConfigFile=.*|ConfigFile=Themes/${THEME_VARIANT}.conf|" "$THEME_DIR/metadata.desktop" 2>/dev/null
        VARIANT_CONF="$THEME_DIR/Themes/${THEME_VARIANT}.conf"
        sudo sed -i "s|^HideSessions=.*|HideSessions=false|" "$VARIANT_CONF" 2>/dev/null || true
        sudo sed -i "s|^ShowSessionsButton=.*|ShowSessionsButton=true|" "$VARIANT_CONF" 2>/dev/null || true
        printf "  -> Variant set: $THEME_VARIANT %-25s ${C_GREEN}[ OK ]${RESET}\n" ""
    elif [ -d "$THEME_DIR/Themes" ]; then
        first=$(ls "$THEME_DIR/Themes/" 2>/dev/null | grep '\.conf$' | head -1 | sed 's/\.conf$//')
        if [ -n "$first" ]; then
            sudo sed -i "s|^ConfigFile=.*|ConfigFile=Themes/${first}.conf|" "$THEME_DIR/metadata.desktop" 2>/dev/null
        fi
    fi

    sudo mkdir -p /etc/sddm.conf.d
    sudo tee /etc/sddm.conf >/dev/null <<'EOF'
[Theme]
Current=sddm-astronaut-theme
EOF

    if [[ "$SDDM_WAYLAND" == true ]]; then
        sudo tee /etc/sddm.conf.d/10-wayland.conf >/dev/null <<'EOF'
[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_DISABLE_WINDOWDECORATION=1
EOF
    fi

    sudo tee /etc/sddm.conf.d/virtualkbd.conf >/dev/null <<'EOF'
[General]
InputMethod=qtvirtualkeyboard
EOF
    printf "  -> SDDM Astronaut configured %-18s ${C_GREEN}[ OK ]${RESET}\n" ""
fi

# Hyprland session check
HYPR_SESSION="/usr/share/wayland-sessions/hyprland.desktop"
if [ -f "$HYPR_SESSION" ]; then
    if pacman -Qo "$HYPR_SESSION" &>/dev/null; then
        printf "  -> Hyprland session (pacman-owned) %-13s ${C_GREEN}[ OK ]${RESET}\n" ""
    else
        sudo rm -f "$HYPR_SESSION"
        sudo pacman -S --needed --noconfirm hyprland 2>/dev/null
    fi
elif pacman -Q hyprland &>/dev/null; then
    sudo pacman -S --needed --noconfirm hyprland
fi

if [ -f /usr/share/wayland-sessions/hyprland-uwsm.desktop ]; then
    printf "  -> Hyprland-uwsm session available %-13s ${C_GREEN}[ OK ]${RESET}\n" ""
fi

# Trigger Template Compilation
if [ -f "$TARGET_CONFIG_DIR/hypr/scripts/settings_watcher.sh" ]; then
    chmod +x "$TARGET_CONFIG_DIR/hypr/scripts/settings_watcher.sh"
    bash "$TARGET_CONFIG_DIR/hypr/scripts/settings_watcher.sh" --compile 2>/dev/null || true
fi

# --- 8. Persist version state ---
cat <<EOF > "$VERSION_FILE"
LOCAL_VERSION="$DOTS_VERSION"
LAST_COMMIT="$NEW_COMMIT"
WEATHER_API_KEY="$WEATHER_API_KEY"
WEATHER_CITY_ID="$WEATHER_CITY_ID"
WEATHER_UNIT="$WEATHER_UNIT"
DRIVER_CHOICE="$DRIVER_CHOICE"
KB_LAYOUTS="$KB_LAYOUTS"
KB_LAYOUTS_DISPLAY="$KB_LAYOUTS_DISPLAY"
KB_OPTIONS="$KB_OPTIONS"
WALLPAPER_DIR="$WALLPAPER_DIR"
LITELLM_KEY="$LITELLM_KEY"
AUTOBROWSE_AUTH_TOKEN="$AUTOBROWSE_AUTH_TOKEN"
EOF
chmod 600 "$VERSION_FILE"

rm -f ~/.cache/quickshell/updater/update_pending
rm -f ~/.local/state/quickshell/wallpaper_picker/wallpaper_initialized

printf "  -> Configuration saved %-25s ${C_GREEN}[ OK ]${RESET}\n" ""


# ==============================================================================
# Optional security hardening
# ==============================================================================
echo -e "\n${C_CYAN}[ INFO ]${RESET} Optional security hardening..."

# 1. Firewall — block inbound by default. ufw is simple; nftables is the systemd-native option.
if command -v ufw &>/dev/null; then
    if ! sudo ufw status 2>/dev/null | grep -q "active"; then
        printf "  -> ${BOLD}ufw is installed but inactive${RESET}\n"
        printf "     Run: ${C_GREEN}sudo ufw default deny incoming && sudo ufw default allow outgoing && sudo ufw enable${RESET}\n"
    else
        printf "  -> ufw active %-33s ${C_GREEN}[ OK ]${RESET}\n" ""
    fi
else
    printf "  -> ${C_YELLOW}No firewall configured.${RESET} Consider: ${BOLD}sudo pacman -S ufw && sudo systemctl enable --now ufw${RESET}\n"
fi

# 2. AppArmor / SELinux — most Arch boxes have neither. If you want MAC, see:
#    https://wiki.archlinux.org/title/AppArmor
#    Adding it post-install is harder than during install. Skipping by default.

# 3. systemd-resolved over Pi-hole? If you want local DNS encryption to your DNS server,
#    edit /etc/systemd/resolved.conf — DNSOverTLS=yes and set DNS=1.1.1.2 (or your pi-hole).

# 4. Hardened malloc (replaces glibc malloc with security-focused alternative)
#    Not enabled by default — breaks some apps. To try:
#    paru -S hardened-malloc-git
#    Then in apps you trust: LD_PRELOAD=/usr/lib/libhardened_malloc.so myapp

# 5. Disable telemetry in your packages — already done for our install.sh.
#    Other potential leaks: GTK file chooser recently used, KDE/Akonadi if installed.

# 6. Browser: consider librewolf or mullvad-browser instead of Firefox
#    paru -S librewolf-bin   # or mullvad-browser-bin

printf "  -> See top of install.sh for the full hardening checklist\n"


# ==============================================================================
# Final Output
# ==============================================================================
echo -e "\n${BOLD}${C_GREEN}"
cat << "EOF"
 ___ _  _ ___ _____ _   _    _      _ _____ ___ ___  _  _    ___ ___  __  __ ___ _    ___ _____ ___
|_ _| \| / __|_   _/_\ | |  | |    /_\_   _|_ _/ _ \| \| |  / __/ _ \ | \/  | _ \ |  | __|_   _| __|
 | || .` \__ \ | |/ _ \| |__| |__ / _ \| |  | | (_) | .` | | (_| (_) | |\/| |  _/ |__| _|  | | | _|
|___|_|\_|___/ |_/_/ \_\____|____/_/ \_\_| |___\___/|_|\_|  \___\___/|_|  |_|_| |____|___| |_| |___|

EOF
echo -e "${RESET}\n"

if [ ${#FAILED_PKGS[@]} -ne 0 ]; then
    echo -e "${BOLD}${C_RED}The following packages were NOT installed:${RESET}"
    for fp in "${FAILED_PKGS[@]}"; do
        echo -e "  - ${C_YELLOW}$fp${RESET}"
    done
    echo ""
fi

if [ -n "$LITELLM_KEY" ]; then
    echo -e "${BOLD}LiteLLM URL:${RESET} ${C_GREEN}http://localhost:4000${RESET}"
    echo -e "${BOLD}LiteLLM key:${RESET} ${C_GREEN}$LITELLM_KEY${RESET}"
    echo -e "${DIM}(also stored in $AI_CFG and $HERMES_CFG)${RESET}\n"
fi

echo -e "Old configurations backed up to: ${C_CYAN}$BACKUP_DIR${RESET}"
echo -e "Log out and log back in, or restart Hyprland to apply all changes."

# Render node check — Hyprland's aquamarine backend needs a working DRM render
# node. Most common cause of grey-screen-on-launch in VMs is a missing render
# node (the VM has no virtio-gl or hardware passthrough).
if [ "$GPU_VENDOR" = "VM" ]; then
    if ! ls /dev/dri/renderD* &>/dev/null; then
        echo -e "\n${BOLD}${C_YELLOW}⚠ VM render node missing (/dev/dri/renderD128)${RESET}"
        echo -e "${C_YELLOW}Hyprland will FAIL with 'no matching devices found' in aquamarine.${RESET}"
        echo -e "${C_YELLOW}On the Proxmox host, enable virtio-gl for this VM:${RESET}"
        echo -e "  ${C_GREEN}qm stop <vmid>${RESET}"
        echo -e "  ${C_GREEN}qm set <vmid> --vga virtio-gl,memory=128${RESET}"
        echo -e "  ${C_GREEN}qm start <vmid>${RESET}"
    fi
fi

echo -e "\nNext steps:"
echo -e "  1. ${C_GREEN}ollama pull qwen2.5:7b${RESET}"
echo -e "  2. Edit ${C_GREEN}$AI_CFG${RESET} (Lichess + Kavita keys)"
if command -v hermes &>/dev/null; then
    echo -e "  3. Run ${C_GREEN}hermes${RESET} once to confirm config"
fi
echo -e "  4. ${C_GREEN}sudo reboot${RESET} for SDDM"
