#!/bin/bash

# Detectar navegador default
DESKTOP_FILE=$(xdg-settings get default-web-browser 2>/dev/null)

# Mapear .desktop → binario y clase de ventana en Hyprland
case "$DESKTOP_FILE" in
    zen*.desktop|zen-browser*.desktop)
        BROWSER_BIN="zen-browser"
        BROWSER_CLASS="zen"
        BROWSER_ENGINE="gecko"
        ;;
    firefox*.desktop)
        BROWSER_BIN="firefox"
        BROWSER_CLASS="firefox"
        BROWSER_ENGINE="gecko"
        ;;
    google-chrome*.desktop)
        BROWSER_BIN="google-chrome-stable"
        BROWSER_CLASS="google-chrome"
        BROWSER_ENGINE="chromium"
        ;;
    chromium*.desktop)
        BROWSER_BIN="chromium"
        BROWSER_CLASS="chromium"
        BROWSER_ENGINE="chromium"
        ;;
    brave*.desktop)
        BROWSER_BIN="brave"
        BROWSER_CLASS="brave-browser"
        BROWSER_ENGINE="chromium"
        ;;
    microsoft-edge*.desktop)
        BROWSER_BIN="microsoft-edge"
        BROWSER_CLASS="microsoft-edge"
        BROWSER_ENGINE="chromium"
        ;;
    opera*.desktop)
        BROWSER_BIN="opera"
        BROWSER_CLASS="opera"
        BROWSER_ENGINE="chromium"
        ;;
    *)
        # Fallback: usar xdg-open
        xdg-open https://web.whatsapp.com &
        exit 0
        ;;
esac

WHATSAPP_URL="https://web.whatsapp.com"

browser_exists_in_normal() {
    local count
    count=$(hyprctl clients -j | jq -r --arg cls "$BROWSER_CLASS" \
        '.[] | select(.class == $cls and .workspace.name != "special") | .address' | wc -l)
    [ "$count" -gt 0 ]
}

get_browser_in_normal() {
    hyprctl clients -j | jq -r --arg cls "$BROWSER_CLASS" \
        '.[] | select(.class == $cls and .workspace.name != "special") | .address'
}

focus_normal_browser() {
    local addr
    addr=$(get_browser_in_normal | head -n1)
    if [ -n "$addr" ]; then
        hyprctl dispatch focuswindow "address:$addr"
        return 0
    fi
    return 1
}

launch_browser() {
    local mode="$1"  # new-tab | new-instance | fresh

    if [ "$BROWSER_ENGINE" = "gecko" ]; then
        export MOZ_ENABLE_WAYLAND=1
        case "$mode" in
            new-tab)      "$BROWSER_BIN" --new-tab "$WHATSAPP_URL" & ;;
            new-instance) "$BROWSER_BIN" --new-instance "$WHATSAPP_URL" & ;;
            fresh)        "$BROWSER_BIN" "$WHATSAPP_URL" & ;;
        esac
    else
        # Chromium-based: abrir URL directamente (browser decide si nueva pestaña o ventana)
        "$BROWSER_BIN" "$WHATSAPP_URL" &
    fi
}

if browser_exists_in_normal; then
    launch_browser "new-tab"
    sleep 1
    focus_normal_browser

elif pgrep -f "$BROWSER_BIN" > /dev/null; then
    # Solo en special workspace
    launch_browser "new-instance"
    sleep 4
    focus_normal_browser

else
    launch_browser "fresh"
    sleep 4
    focus_normal_browser
fi
