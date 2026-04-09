#!/bin/bash
# /* ---- 💫 Script de Modo Juego Mejorado y Sincronizado ---- */

# --- CONFIGURACIÓN ---
# ¡Valores extraídos de tu UserDecorations.conf!
GAPS_IN=2
GAPS_OUT=4
BORDER_SIZE=2
ROUNDING=10

# --- RUTAS ---
NOTIF_ICON="$HOME/.config/swaync/images/ja.png"
WALLPAPER="$HOME/.config/rofi/.current_wallpaper" 
WALLPAPER_PIDFILE="/tmp/wallpaper_auto_change.pid"
WALLPAPER_APPLY_SCRIPT="$HOME/.config/hypr/UserScripts/WallpaperApply.sh"

# --- LÓGICA ---
LOCK_FILE="/tmp/gamemode.lock"
WALLPAPER_DIR="$HOME/Pictures/wallpapers"

stop_quickshell_full() {
    # Cerrar cualquier instancia de Quickshell (binario quickshell o wrapper qs).
    pkill -x quickshell 2>/dev/null || true
    pkill -x qs 2>/dev/null || true
    pkill -f '/quickshell' 2>/dev/null || true
    sleep 0.2
    pkill -9 -x quickshell 2>/dev/null || true
    pkill -9 -x qs 2>/dev/null || true
}

stop_wallpaper_stack_full() {
    # Detener rotadores/scripts de cambio de fondo.
    pkill -f "WallpaperAutoChange.sh" 2>/dev/null || true
    pkill -f "WallpaperRandom.sh" 2>/dev/null || true
    pkill -f "WallpaperNext.sh" 2>/dev/null || true

    # Si existe PID del auto-change legacy, detenerlo y limpiar pidfile.
    if [ -f "$WALLPAPER_PIDFILE" ]; then
        wp_pid="$(cat "$WALLPAPER_PIDFILE" 2>/dev/null || true)"
        if [ -n "$wp_pid" ]; then
            kill "$wp_pid" 2>/dev/null || true
        fi
        rm -f "$WALLPAPER_PIDFILE"
    fi

    # Detener daemons/backends de wallpaper para liberar recursos al 100%.
    pkill -x mpvpaper 2>/dev/null || true
    pkill -x swaybg 2>/dev/null || true
    pkill -x hyprpaper 2>/dev/null || true
    pkill -x awww-daemon 2>/dev/null || true
    awww kill 2>/dev/null || true
}

restore_wallpaper_once() {
    if [ ! -e "$WALLPAPER" ]; then
        return
    fi

    current_wall="$(readlink -f "$WALLPAPER" 2>/dev/null || true)"
    if [ -z "$current_wall" ]; then
        current_wall="$WALLPAPER"
    fi

    if [ -x "$WALLPAPER_APPLY_SCRIPT" ]; then
        "$WALLPAPER_APPLY_SCRIPT" image "$current_wall" >/dev/null 2>&1 || true
        return
    fi

    # Fallback por compatibilidad si no existe WallpaperApply.sh
    if ! pgrep -x awww-daemon >/dev/null; then
        awww-daemon --format xrgb >/dev/null 2>&1 &
        sleep 1
    fi
    awww img "$current_wall" >/dev/null 2>&1 || true
}

start_quickshell_if_needed() {
    if ! pgrep -x quickshell >/dev/null && ! pgrep -x qs >/dev/null; then
        nohup quickshell >/dev/null 2>&1 &
    fi
}

if [ -f "$LOCK_FILE" ]; then
    # --- DESACTIVAR MODO JUEGO ---
    hyprctl --batch "\
        keyword animations:enabled 1;\
        keyword decoration:blur:enabled 1;\
        keyword decoration:shadow:enabled 1;\
        keyword decoration:dim_inactive 1;\
        keyword decoration:active_opacity 1.0;\
        keyword decoration:inactive_opacity 0.9;\
        keyword general:gaps_in $GAPS_IN;\
        keyword general:gaps_out $GAPS_OUT;\
        keyword general:border_size $BORDER_SIZE;\
        keyword decoration:rounding $ROUNDING;\
        keyword misc:vfr 1;\
        keyword misc:vrr 0"

    hyprctl keyword windowrule "opacity,^(.*)$"
    
    # Reanudar swaync (NO matarlo, solo descongelarlo)
    pkill -CONT swaync 2>/dev/null
    
    # Reiniciar waybar solamente
    if pidof waybar >/dev/null; then
        pkill waybar
    fi
    killall -SIGUSR2 waybar 2>/dev/null
    
    sleep 1
    waybar &
    
    # Restaurar quickshell y fondo al salir del modo juego.
    start_quickshell_if_needed
    restore_wallpaper_once
    
    rm "$LOCK_FILE"
    notify-send -u normal -i "$NOTIF_ICON" "🎮 Modo Juego: Desactivado" "Configuración visual restaurada.\n✅ Efectos reactivados\n✅ Notificaciones activas"
else
    # --- ACTIVAR MODO JUEGO ---
    touch "$LOCK_FILE"
    hyprctl --batch "\
        keyword animations:enabled 0;\
        keyword decoration:blur:enabled 0;\
        keyword decoration:shadow:enabled 0;\
        keyword decoration:dim_inactive 0;\
        keyword decoration:active_opacity 1.0;\
        keyword decoration:inactive_opacity 1.0;\
        keyword general:gaps_in 0;\
        keyword general:gaps_out 0;\
        keyword general:border_size 1;\
        keyword decoration:rounding 0;\
        keyword misc:vfr 0;\
        keyword misc:vrr 2"
    
    # Ocultar Waybar
    pkill -USR1 waybar
    
    # Pausar/matar notificaciones (swaync)
    pkill -STOP swaync 2>/dev/null
    
    # Detener quickshell y toda la pila de wallpapers para liberar recursos al maximo.
    stop_quickshell_full
    stop_wallpaper_stack_full
    
    # Opcional: Pausar otros daemons innecesarios
    # pkill -STOP rog-control-center 2>/dev/null
    
    notify-send -u low -i "$NOTIF_ICON" "🎮 Modo Juego: Activado" "Máximo rendimiento activado.\n⚡ Animaciones OFF\n⚡ Blur/Sombras OFF\n⚡ Notificaciones pausadas\n⚡ VRR activado"
fi