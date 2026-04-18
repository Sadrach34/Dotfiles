#!/usr/bin/env bash
SCRIPT="$HOME/.config/quickshell/scripts/python/config_panel.py"
LOG_DIR="$HOME/.cache/quickshell"
LOG_FILE="$LOG_DIR/config-panel.log"

mkdir -p "$LOG_DIR"

# Recover from stale background processes: if one exists, stop it first.
if pgrep -f "config_panel.py" > /dev/null 2>&1; then
    pkill -f "config_panel.py"
    exit 0
fi

nohup env \
    WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}" \
    XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" \
    DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}" \
    python3 "$SCRIPT" >> "$LOG_FILE" 2>&1 &
