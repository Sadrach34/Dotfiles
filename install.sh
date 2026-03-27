#!/bin/bash
# ============================================================
#   Dotfiles Installer - Sadrach
#   github.com/Sadrach34/dotfiles
#
#   Target hardware:
#     CPU : Intel i7-4800MQ (Haswell, 4ª gen)
#     GPU : Intel HD Graphics 4600 (integrada, Gen 7.5)
#     Kernel: linux-cachyos (principal) + linux-lts (respaldo)
#
#   Qué hace este script:
#     1. Agrega repos CachyOS (keyring + mirrorlist)
#     2. Instala kernels cachyos + lts
#     3. Drivers correctos para Haswell (libva-intel-driver, NO intel-media-driver)
#     4. Optimizaciones CachyOS (ananicy-cpp, bfq scheduler, powersave governor)
#     5. Elimina bspwm y toda su configuración
#     6. Instala todos los paquetes
#     7. Clona y aplica dotfiles (con backup de lo existente)
#     8. Configura servicios y zsh
# ============================================================

set -e

# ── Colores ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${CYAN}${BOLD}[INFO]${NC}  $1"; }
ok()      { echo -e "${GREEN}${BOLD}[ OK ]${NC}  $1"; }
warn()    { echo -e "${YELLOW}${BOLD}[WARN]${NC}  $1"; }
error()   { echo -e "${RED}${BOLD}[ERR ]${NC}  $1"; exit 1; }
section() { echo -e "\n${BLUE}${BOLD}━━━  $1  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

GITHUB_USER="Sadrach34"
DOTFILES_REPO="https://github.com/${GITHUB_USER}/dotfiles.git"
DOTFILES_DIR="$HOME/.dotfiles"

# ════════════════════════════════════════════════════════════
section "Instalador de dotfiles - Sadrach"
# ════════════════════════════════════════════════════════════
echo ""
echo -e "  ${BOLD}Hardware objetivo:${NC}"
echo -e "   CPU : Intel i7-4800MQ (Haswell)"
echo -e "   GPU : Intel HD Graphics 4600 (iGPU Gen 7.5)"
echo -e "   Kernel: linux-cachyos (principal) + linux-lts (respaldo)"
echo ""
echo -e "  ${BOLD}Este script va a:${NC}"
echo -e "   1.  Agregar repos de CachyOS"
echo -e "   2.  Instalar kernels cachyos + lts"
echo -e "   3.  Instalar drivers Intel correctos para Haswell"
echo -e "   4.  Aplicar optimizaciones CachyOS (bfq, ananicy, powersave)"
echo -e "   5.  Eliminar bspwm y toda su configuración"
echo -e "   6.  Instalar todos tus paquetes"
echo -e "   7.  Clonar y aplicar tus dotfiles (backup de lo existente)"
echo -e "   8.  Configurar servicios y zsh"
echo ""
warn "Tus archivos personales (Documentos, Imágenes, etc.) NO se tocan."
warn "Todo lo que choque con tus dotfiles se mueve a ~/.dotfiles-backup-FECHA/"
echo ""
read -rp "$(echo -e ${YELLOW}"¿Continuar? [s/N]: "${NC})" confirm
[[ "$confirm" =~ ^[sS]$ ]] || { echo "Cancelado."; exit 0; }

# ════════════════════════════════════════════════════════════
section "1. Sistema base"
# ════════════════════════════════════════════════════════════
info "Actualizando sistema..."
sudo pacman -Syu --noconfirm

info "Instalando dependencias mínimas..."
sudo pacman -S --needed --noconfirm \
    base-devel git curl wget zsh gnupg

# ════════════════════════════════════════════════════════════
section "2. Repositorios de CachyOS"
# ════════════════════════════════════════════════════════════
if grep -q "\[cachyos\]" /etc/pacman.conf 2>/dev/null; then
    ok "Repos de CachyOS ya configurados"
else
    info "Agregando repos de CachyOS..."
    cd /tmp

    info "  → cachyos-keyring..."
    git clone https://aur.archlinux.org/cachyos-keyring.git --depth=1
    cd cachyos-keyring && makepkg -si --noconfirm && cd /tmp

    info "  → cachyos-mirrorlist..."
    git clone https://aur.archlinux.org/cachyos-mirrorlist.git --depth=1
    cd cachyos-mirrorlist && makepkg -si --noconfirm && cd /tmp

    info "  → cachyos-v3-mirrorlist..."
    git clone https://aur.archlinux.org/cachyos-v3-mirrorlist.git --depth=1
    cd cachyos-v3-mirrorlist && makepkg -si --noconfirm && cd /tmp

    info "Configurando pacman.conf..."
    sudo tee -a /etc/pacman.conf > /dev/null << 'PACMANEOF'

# CachyOS repos
[cachyos-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

[cachyos]
Include = /etc/pacman.d/cachyos-mirrorlist
PACMANEOF

    sudo pacman -Syu --noconfirm
    ok "Repos de CachyOS configurados"
fi

# ════════════════════════════════════════════════════════════
section "3. Kernels: CachyOS (principal) + LTS (respaldo)"
# ════════════════════════════════════════════════════════════
info "Instalando linux-cachyos y linux-lts..."
sudo pacman -S --needed --noconfirm \
    linux-cachyos \
    linux-cachyos-headers \
    linux-lts \
    linux-lts-headers \
    linux-firmware

ok "Kernels instalados"
info "Al arrancar verás en GRUB:"
info "  → linux-cachyos  (kernel principal optimizado)"
info "  → linux-lts      (respaldo / safe mode)"

# ════════════════════════════════════════════════════════════
section "4. Intel ucode + drivers para Haswell (iGPU Gen 7.5)"
# ════════════════════════════════════════════════════════════

# NOTA IMPORTANTE:
# El i7-4800MQ tiene Intel HD 4600 (Haswell = Gen 7.5)
# - intel-media-driver  → Solo Gen 8+ (Broadwell en adelante) → NO usar
# - libva-intel-driver  → Gen 4-9 (Haswell incluido) → CORRECTO
# - vulkan-intel        → Haswell soporta Vulkan 1.0 parcial, se instala pero limitado

info "Instalando intel-ucode (microcódigo para i7-4800MQ)..."
sudo pacman -S --needed --noconfirm intel-ucode

info "Instalando drivers Intel Haswell correctos..."
sudo pacman -S --needed --noconfirm \
    mesa \
    lib32-mesa \
    libva-intel-driver \
    lib32-libva-intel-driver \
    libva-utils \
    vulkan-intel \
    lib32-vulkan-intel \
    vulkan-tools \
    intel-gpu-tools

ok "Drivers Intel Haswell instalados"

# Configurar VA-API para Haswell (driver i965, no iHD)
info "Configurando VA-API para Haswell (driver i965)..."
ENVFILE="/etc/environment"
if ! grep -q "LIBVA_DRIVER_NAME" "$ENVFILE" 2>/dev/null; then
    # Haswell usa i965, NO iHD (ese es para Gen 8+)
    echo "LIBVA_DRIVER_NAME=i965" | sudo tee -a "$ENVFILE" > /dev/null
    ok "VA-API configurado → i965 (correcto para Haswell)"
else
    # Si ya existe pero dice iHD, corregirlo
    sudo sed -i 's/LIBVA_DRIVER_NAME=iHD/LIBVA_DRIVER_NAME=i965/g' "$ENVFILE"
    ok "VA-API verificado → i965"
fi

# ════════════════════════════════════════════════════════════
section "5. GRUB"
# ════════════════════════════════════════════════════════════
info "Instalando GRUB y efibootmgr..."
sudo pacman -S --needed --noconfirm grub efibootmgr os-prober

# Habilitar os-prober en grub (para detectar otros SO si los hay)
if grep -q "#GRUB_DISABLE_OS_PROBER" /etc/default/grub 2>/dev/null; then
    sudo sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
fi

info "Generando configuración de GRUB..."
sudo grub-mkconfig -o /boot/grub/grub.cfg
ok "GRUB configurado"

# ════════════════════════════════════════════════════════════
section "6. Optimizaciones CachyOS (igual que tu escritorio)"
# ════════════════════════════════════════════════════════════

# --- CPU Governor: powersave (igual que tu escritorio) ---
info "Configurando CPU governor → powersave..."
sudo pacman -S --needed --noconfirm cpupower
sudo tee /etc/default/cpupower > /dev/null << 'EOF'
governor='powersave'
EOF
sudo systemctl enable --now cpupower
ok "CPU governor: powersave"

# --- I/O Scheduler: bfq (igual que tu escritorio) ---
# bfq es ideal para laptops con HDD o SSD SATA (Haswell-era)
info "Configurando I/O scheduler → bfq..."
sudo tee /etc/udev/rules.d/60-ioschedulers.rules > /dev/null << 'EOF'
# BFQ para todos los discos rotativos y SSD SATA
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="bfq"
ACTION=="add|change", KERNEL=="nvme*", ATTR{queue/scheduler}="none"
EOF
ok "I/O scheduler: bfq configurado"

# --- ananicy-cpp: prioridades automáticas de procesos ---
info "Instalando ananicy-cpp + reglas CachyOS..."
sudo pacman -S --needed --noconfirm ananicy-cpp cachyos-ananicy-rules
ok "ananicy-cpp listo"

# --- zram: swap comprimido en RAM (bueno para 16GB) ---
info "Configurando zram..."
sudo pacman -S --needed --noconfirm zram-generator
sudo tee /etc/systemd/zram-generator.conf > /dev/null << 'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOF
ok "zram configurado (ram/2 con zstd)"

# --- irqbalance: distribuye interrupciones entre cores ---
info "Instalando irqbalance..."
sudo pacman -S --needed --noconfirm irqbalance
sudo systemctl enable --now irqbalance
ok "irqbalance activo"

# --- power-profiles-daemon ---
sudo pacman -S --needed --noconfirm power-profiles-daemon
sudo systemctl enable --now power-profiles-daemon
ok "power-profiles-daemon activo"

# ════════════════════════════════════════════════════════════
section "7. Eliminando bspwm y toda su configuración"
# ════════════════════════════════════════════════════════════
info "Desinstalando bspwm y paquetes relacionados..."

BSPWM_PKGS=(bspwm sxhkd polybar picom nitrogen rofi-bspwm)
for pkg in "${BSPWM_PKGS[@]}"; do
    if pacman -Qq "$pkg" &>/dev/null; then
        sudo pacman -Rns --noconfirm "$pkg" 2>/dev/null && ok "Desinstalado: $pkg" || warn "No se pudo desinstalar: $pkg"
    fi
done

info "Eliminando archivos de configuración de bspwm..."
BSPWM_CONFIGS=(
    "$HOME/.config/bspwm"
    "$HOME/.config/sxhkd"
    "$HOME/.config/polybar"
    "$HOME/.config/picom"
)
for cfg in "${BSPWM_CONFIGS[@]}"; do
    if [ -d "$cfg" ] || [ -f "$cfg" ]; then
        rm -rf "$cfg"
        ok "Eliminado: $cfg"
    fi
done

info "Eliminando sesiones de bspwm en display managers..."
sudo rm -f /usr/share/xsessions/bspwm.desktop 2>/dev/null || true
sudo rm -f /usr/share/wayland-sessions/bspwm.desktop 2>/dev/null || true

ok "bspwm eliminado completamente"

# ════════════════════════════════════════════════════════════
section "8. Instalando yay (AUR helper)"
# ════════════════════════════════════════════════════════════
if command -v yay &>/dev/null; then
    ok "yay ya está instalado"
else
    info "Instalando yay..."
    cd /tmp
    git clone https://aur.archlinux.org/yay.git --depth=1
    cd yay && makepkg -si --noconfirm
    cd ~
    ok "yay instalado"
fi

# ════════════════════════════════════════════════════════════
section "9. Paquetes oficiales + CachyOS"
# ════════════════════════════════════════════════════════════
info "Instalando paquetes (esto tarda varios minutos)..."

OFFICIAL_PKGS=(
    # Sistema
    base base-devel dkms
    inetutils btrfs-progs ntfs-3g
    scx-scheds sof-firmware
    # CachyOS
    cachyos-ananicy-rules ananicy-cpp
    cachyos-rate-mirrors
    # Wayland / Hyprland
    hyprland hypridle hyprlock
    hyprpolkitagent uwsm
    xdg-desktop-portal-hyprland
    xdg-user-dirs xdg-utils
    qt5-wayland qt6-wayland
    qt5ct qt6ct kvantum
    qt6-imageformats qt6-tools
    qt6-virtualkeyboard
    xorg-server xorg-xinit
    # Theming
    adw-gtk-theme nwg-look
    gtk-engine-murrine
    # Audio
    pipewire pipewire-alsa
    pipewire-jack pipewire-pulse
    wireplumber gst-plugin-pipewire
    pavucontrol pamixer pwvucontrol
    alsa-utils easyeffects calf
    libpulse sox speech-dispatcher espeak-ng
    # Bar / Shell / Notifs
    waybar swww swaync wlogout
    fuzzel rofi wofi
    cliphist wl-clip-persist
    wlsunset wtype xdotool ydotool
    # Fuentes
    adobe-source-code-pro-fonts
    noto-fonts noto-fonts-cjk noto-fonts-emoji
    otf-font-awesome ttf-droid
    ttf-roboto ttf-roboto-mono
    ttf-fira-code ttf-firacode-nerd
    ttf-fantasque-nerd
    ttf-jetbrains-mono ttf-jetbrains-mono-nerd
    ttf-nerd-fonts-symbols
    # Terminal
    kitty tmux zsh zsh-completions
    zbar bc nano vim
    # File manager
    thunar thunar-archive-plugin
    thunar-volman tumbler
    ffmpegthumbnailer gvfs gvfs-mtp
    xarchiver unrar unzip mousepad
    # Red / Bluetooth
    networkmanager network-manager-applet
    iwd ethtool wireless_tools nmap socat
    blueman bluez-utils
    # Multimedia
    mpv mpv-mpris vlc
    obs-studio gpu-screen-recorder
    audacity kdenlive
    grim slurp swappy
    imagemagick chafa playerctl
    # Gaming
    steam gamemode lib32-gamemode
    gamescope mangohud goverlay
    protonplus protontricks
    wine-staging lib32-mpg123
    # Desarrollo
    git github-cli rustup
    jdk-openjdk tk pyenv
    python-pip python-pipx
    python-matplotlib python-requests
    python-pyquery mercurial
    mariadb postgresql flatpak
    # Utils
    btop htop ncdu tree lsd fzf gum
    fastfetch inxi smartmontools
    nvme-cli usbutils brightnessctl ddcutil
    ufw firejail pacman-contrib reflector
    timeshift syncthing
    android-tools android-udev android-file-transfer
    f3 bsd-games
    tesseract tesseract-data-eng tesseract-data-spa
    tesseract-data-chi_sim tesseract-data-chi_tra
    tesseract-data-jpn tesseract-data-kor tesseract-data-lat
    # Apps
    firefox bitwarden discord
    obsidian onlyoffice-bin blender
    kdiskmark qalculate-gtk
    gnome-system-monitor loupe piper cups
    # Extras
    yad cava matugen wallust
    nwg-displays vdpauinfo libspng
    mesa-demos mesa-utils umockdev
    pokemon-colorscripts-git
    quickshell-git
)

sudo pacman -S --needed --noconfirm "${OFFICIAL_PKGS[@]}" || \
    warn "Algunos paquetes fallaron, continuando..."

ok "Paquetes oficiales instalados"

# ════════════════════════════════════════════════════════════
section "10. Paquetes AUR"
# ════════════════════════════════════════════════════════════
AUR_PKGS=(
    8188eu-dkms-git
    ascii-image-converter
    aylurs-gtk-shell-git
    gradia
    jetbrains-toolbox
    mpvpaper
    mycli
    pacman4console
    piper-tts-bin
    ttf-league-gothic
    ttf-ms-fonts
    ttf-phosphor-icons
    ttf-victor-mono
    unimatrix-git
    upscayl-appimage
    visual-studio-code-bin
    warp-terminal
    yt-dlp-git
)

info "Instalando paquetes AUR..."
yay -S --needed --noconfirm "${AUR_PKGS[@]}" || \
    warn "Algunos paquetes AUR fallaron, revisa manualmente después"

ok "Paquetes AUR instalados"

# ════════════════════════════════════════════════════════════
section "11. Clonando y aplicando dotfiles"
# ════════════════════════════════════════════════════════════
if [ -d "$DOTFILES_DIR" ]; then
    warn "Ya existe $DOTFILES_DIR — haciendo backup..."
    mv "$DOTFILES_DIR" "${DOTFILES_DIR}.bak.$(date +%Y%m%d%H%M%S)"
fi

info "Clonando dotfiles desde GitHub..."
git clone --bare "$DOTFILES_REPO" "$DOTFILES_DIR"

# Backup automático de lo que choque
BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d%H%M%S)"
mkdir -p "$BACKUP_DIR"

info "Detectando conflictos y haciendo backup..."
git --git-dir="$DOTFILES_DIR/" --work-tree="$HOME" checkout 2>&1 \
    | grep -E "ya existe|already exists|overwrite" \
    | awk '{print $1}' \
    | while read -r file; do
        mkdir -p "$BACKUP_DIR/$(dirname "$file")"
        mv "$HOME/$file" "$BACKUP_DIR/$file" 2>/dev/null || true
    done

info "Aplicando dotfiles..."
git --git-dir="$DOTFILES_DIR/" --work-tree="$HOME" checkout
git --git-dir="$DOTFILES_DIR/" --work-tree="$HOME" config status.showUntrackedFiles no

ok "Dotfiles aplicados"
if [ -d "$BACKUP_DIR" ] && [ "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
    warn "Configs previas respaldadas en: $BACKUP_DIR"
fi

# ════════════════════════════════════════════════════════════
section "12. Alias dotfiles en zsh"
# ════════════════════════════════════════════════════════════
ZSHRC="$HOME/.zshrc"
ALIAS_LINE="alias dotfiles='git --git-dir=\$HOME/.dotfiles/ --work-tree=\$HOME'"

if ! grep -q "alias dotfiles" "$ZSHRC" 2>/dev/null; then
    { echo ""; echo "# Dotfiles bare repo"; echo "$ALIAS_LINE"; } >> "$ZSHRC"
    ok "Alias agregado a .zshrc"
else
    ok "Alias ya existe en .zshrc"
fi

# ════════════════════════════════════════════════════════════
section "13. Zsh como shell por defecto"
# ════════════════════════════════════════════════════════════
if [ "$SHELL" != "$(which zsh)" ]; then
    chsh -s "$(which zsh)"
    ok "Shell cambiado a zsh"
else
    ok "Zsh ya es tu shell"
fi

# ════════════════════════════════════════════════════════════
section "14. Servicios del sistema"
# ════════════════════════════════════════════════════════════
SERVICES=(
    NetworkManager
    bluetooth
    sddm
    cups
    ufw
    irqbalance
    power-profiles-daemon
    ananicy-cpp
)

for svc in "${SERVICES[@]}"; do
    sudo systemctl enable --now "$svc" 2>/dev/null \
        && ok "$svc habilitado" \
        || warn "$svc no se pudo habilitar"
done

systemctl --user enable --now syncthing 2>/dev/null \
    && ok "Syncthing (usuario) habilitado" \
    || warn "Syncthing no habilitado"

# ════════════════════════════════════════════════════════════
section "15. Regenerar initramfs y GRUB final"
# ════════════════════════════════════════════════════════════
info "Regenerando initramfs para todos los kernels..."
sudo mkinitcpio -P

info "Actualizando GRUB..."
sudo grub-mkconfig -o /boot/grub/grub.cfg

ok "initramfs y GRUB actualizados"

# ════════════════════════════════════════════════════════════
echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║   ¡Instalación completa!                         ║${NC}"
echo -e "${GREEN}${BOLD}║                                                  ║${NC}"
echo -e "${GREEN}${BOLD}║   Optimizaciones aplicadas:                      ║${NC}"
echo -e "${GREEN}${BOLD}║    ✓ CPU governor  : powersave                   ║${NC}"
echo -e "${GREEN}${BOLD}║    ✓ I/O scheduler : bfq                         ║${NC}"
echo -e "${GREEN}${BOLD}║    ✓ ananicy-cpp   : prioridades automáticas      ║${NC}"
echo -e "${GREEN}${BOLD}║    ✓ zram          : swap comprimido (zstd)       ║${NC}"
echo -e "${GREEN}${BOLD}║    ✓ irqbalance    : distribución de interrupciones║${NC}"
echo -e "${GREEN}${BOLD}║    ✓ VA-API        : i965 (correcto para Haswell) ║${NC}"
echo -e "${GREEN}${BOLD}║                                                  ║${NC}"
echo -e "${GREEN}${BOLD}║   Kernels en GRUB:                               ║${NC}"
echo -e "${GREEN}${BOLD}║    → linux-cachyos  (principal)                  ║${NC}"
echo -e "${GREEN}${BOLD}║    → linux-lts      (respaldo / safe mode)       ║${NC}"
echo -e "${GREEN}${BOLD}║                                                  ║${NC}"
echo -e "${GREEN}${BOLD}║   bspwm: desinstalado y configs eliminadas ✓     ║${NC}"
echo -e "${GREEN}${BOLD}║                                                  ║${NC}"
echo -e "${GREEN}${BOLD}║   Reinicia para aplicar todo                     ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo ""
read -rp "$(echo -e ${YELLOW}"¿Reiniciar ahora? [s/N]: "${NC})" reboot_now
[[ "$reboot_now" =~ ^[sS]$ ]] && sudo reboot
