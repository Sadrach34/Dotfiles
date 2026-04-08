#!/bin/bash

# --- Colores para los mensajes ---
GREEN="\e[32m"
BLUE="\e[34m"
YELLOW="\e[33m"
RED="\e[31m"
CYAN="\e[36m"
RESET="\e[0m"

# --- Función para mostrar banner ---
show_banner() {
    echo -e "${CYAN}╔═══════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║       ACTUALIZACIÓN DEL SISTEMA - ARCH        ║${RESET}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════╝${RESET}"
    echo ""
}

# --- Inicio del Script ---
clear
show_banner

WARNINGS=0

sync_databases() {
    local sync_log
    sync_log=$(mktemp)

    if sudo pacman -Sy 2>&1 | tee "$sync_log"; then
        rm -f "$sync_log"
        return 0
    fi

    if grep -qiE "firma|signature" "$sync_log"; then
        echo -e "${YELLOW}⚠ Se detectó un problema de firmas. Intentando reparación automática...${RESET}"
        sudo pacman-key --populate archlinux >/dev/null 2>&1 || true
        sudo pacman-key --refresh-keys >/dev/null 2>&1 || true

        # Reinstala/actualiza keyrings conocidos y reintenta sincronizar.
        sudo pacman -Sy --needed --noconfirm archlinux-keyring cachyos-keyring >/dev/null 2>&1 || \
        sudo pacman -Sy --needed --noconfirm archlinux-keyring >/dev/null 2>&1 || true

        echo -e "${BLUE}Reintentando sincronización de bases de datos...${RESET}"
        if sudo pacman -Syy; then
            rm -f "$sync_log"
            return 0
        fi
    fi

    rm -f "$sync_log"
    return 1
}

echo -e "${BLUE}[1/4] Sincronizando bases de datos de paquetes...${RESET}"
if sync_databases; then
    echo -e "${GREEN}✓ Bases de datos sincronizadas${RESET}\n"
else
    echo -e "${RED}✗ Error al sincronizar bases de datos${RESET}\n"
    echo -e "${YELLOW}Sugerencia: actualiza cachyos-keyring y archlinux-keyring manualmente si el problema persiste.${RESET}\n"
    exit 1
fi

echo -e "${BLUE}[2/4] Actualizando paquetes oficiales...${RESET}"
if sudo pacman -Su --noconfirm; then
    echo -e "${GREEN}✓ Paquetes oficiales actualizados${RESET}\n"
else
    echo -e "${YELLOW}⚠ Algunos paquetes no se pudieron actualizar${RESET}\n"
    WARNINGS=1
fi

echo -e "${BLUE}[3/4] Actualizando paquetes de AUR...${RESET}"
if yay -Sua --noconfirm; then
    echo -e "${GREEN}✓ Paquetes de AUR actualizados${RESET}\n"
else
    echo -e "${YELLOW}⚠ Algunos paquetes de AUR no se pudieron actualizar${RESET}\n"
    WARNINGS=1
fi

echo -e "${BLUE}[4/4] Limpiando caché de paquetes antiguos...${RESET}"
echo -e "${BLUE}  -> Eliminando temporales de descarga incompleta...${RESET}"
download_dirs=$(sudo find /var/cache/pacman/pkg/ -maxdepth 1 -type d -name "download-*" 2>/dev/null)
if [ -n "$download_dirs" ]; then
    if echo "$download_dirs" | sudo xargs -r rm -rf; then
        echo -e "${GREEN}✓ Temporales download-* eliminados${RESET}"
    else
        echo -e "${YELLOW}⚠ No se pudieron eliminar algunos temporales download-*${RESET}"
        WARNINGS=1
    fi
else
    echo -e "${GREEN}✓ No se encontraron temporales download-*${RESET}"
fi

echo -e "${BLUE}  -> Limpiando caché del sistema (paccache)...${RESET}"
if command -v paccache >/dev/null 2>&1; then
    if sudo paccache -r; then
        echo -e "${GREEN}✓ Caché del sistema limpiada con paccache${RESET}"
    else
        echo -e "${YELLOW}⚠ paccache falló, intentando con pacman -Sc${RESET}"
        WARNINGS=1
        if sudo pacman -Sc --noconfirm; then
            echo -e "${GREEN}✓ Caché del sistema limpiada con pacman -Sc${RESET}"
        else
            echo -e "${YELLOW}⚠ No se pudo limpiar la caché del sistema${RESET}"
            WARNINGS=1
        fi
    fi
else
    echo -e "${YELLOW}⚠ paccache no está instalado, usando pacman -Sc${RESET}"
    WARNINGS=1
    if sudo pacman -Sc --noconfirm; then
        echo -e "${GREEN}✓ Caché del sistema limpiada con pacman -Sc${RESET}"
    else
        echo -e "${YELLOW}⚠ No se pudo limpiar la caché del sistema${RESET}"
        WARNINGS=1
    fi
fi

echo -e "${BLUE}  -> Limpiando caché de AUR...${RESET}"
if yay -Sc --aur --noconfirm; then
    echo -e "${GREEN}✓ Caché de AUR limpiada${RESET}\n"
else
    echo -e "${YELLOW}⚠ No se pudo limpiar completamente la caché de AUR${RESET}\n"
    WARNINGS=1
fi

echo -e "${BLUE}[5/5] Limpiando paquetes huérfanos automáticamente...${RESET}"
orphans=$(pacman -Qtdq 2>/dev/null)
if [ -n "$orphans" ]; then
    echo -e "${YELLOW}⚠ Paquetes huérfanos detectados:${RESET}"
    echo "$orphans"
    echo ""

    # Elimina huérfanos junto a sus dependencias no usadas y archivos de configuración.
    if sudo pacman -Rns --noconfirm $orphans; then
        echo -e "${GREEN}✓ Paquetes huérfanos eliminados automáticamente${RESET}\n"
    else
        echo -e "${YELLOW}⚠ No se pudieron eliminar algunos paquetes huérfanos${RESET}\n"
        WARNINGS=1
    fi
else
    echo -e "${GREEN}✓ No se encontraron paquetes huérfanos${RESET}\n"
fi

# --- Finalización del Script ---
echo -e "${CYAN}═══════════════════════════════════════════════${RESET}"
if [ "$WARNINGS" -eq 0 ]; then
    echo -e "${GREEN}✓ ¡Sistema actualizado correctamente!${RESET}"
else
    echo -e "${YELLOW}⚠ Sistema actualizado con advertencias. Revisa los mensajes anteriores.${RESET}"
fi
echo -e "${CYAN}═══════════════════════════════════════════════${RESET}"

# Verificar si se actualizaron componentes críticos
if pacman -Qu 2>/dev/null | grep -qE "linux|systemd"; then
    echo -e "${YELLOW}⚠ IMPORTANTE: Se actualizaron componentes críticos.${RESET}"
    echo -e "${YELLOW}  Es recomendable reiniciar el sistema.${RESET}"
fi

echo ""
read -p "Presiona Enter para salir..."
