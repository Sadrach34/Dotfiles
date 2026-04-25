#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="$HOME/.config/quickshell/data/config.json"

# Optional delay allows Hyprland reload/startup to settle before applying keywords.
if [[ "${1:-}" == "--defer" ]]; then
  sleep 0.5
fi

[[ -f "$CONFIG_FILE" ]] || exit 0

read_json() {
  local expr="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r "$expr" "$CONFIG_FILE" 2>/dev/null || true
  else
    python3 - "$CONFIG_FILE" "$expr" <<'PY'
import json,sys
p=sys.argv[1]
expr=sys.argv[2]
try:
    data=json.load(open(p))
except Exception:
    print("")
    raise SystemExit

def get(path, default=""):
    cur=data
    for key in path:
        if not isinstance(cur, dict):
            return default
        cur=cur.get(key)
        if cur is None:
            return default
    return cur

mapping={
  ".optimization.enabled // false": str(bool(get(["optimization","enabled"], False))).lower(),
  ".optimization.toggles.disableBorders // false": str(bool(get(["optimization","toggles","disableBorders"], False))).lower(),
  ".optimization.toggles.disableTransparency // false": str(bool(get(["optimization","toggles","disableTransparency"], False))).lower(),
  ".optimization.toggles.disableAnimations // false": str(bool(get(["optimization","toggles","disableAnimations"], False))).lower(),
  ".optimization.toggles.disableBlur // false": str(bool(get(["optimization","toggles","disableBlur"], False))).lower(),
  ".optimization.toggles.disableShadows // false": str(bool(get(["optimization","toggles","disableShadows"], False))).lower(),
  ".optimization.toggles.disableRounding // false": str(bool(get(["optimization","toggles","disableRounding"], False))).lower(),
  ".optimization.toggles.disableGaps // false": str(bool(get(["optimization","toggles","disableGaps"], False))).lower(),
  ".optimization.toggles.disableDimInactive // false": str(bool(get(["optimization","toggles","disableDimInactive"], False))).lower(),
}
print(mapping.get(expr, ""))
PY
  fi
}

as_int() {
  [[ "$1" == "true" ]] && echo 1 || echo 0
}

opt_enabled="$(read_json '.optimization.enabled // false')"
disable_borders="$(read_json '.optimization.toggles.disableBorders // false')"
disable_transparency="$(read_json '.optimization.toggles.disableTransparency // false')"
disable_animations="$(read_json '.optimization.toggles.disableAnimations // false')"
disable_blur="$(read_json '.optimization.toggles.disableBlur // false')"
disable_shadows="$(read_json '.optimization.toggles.disableShadows // false')"
disable_rounding="$(read_json '.optimization.toggles.disableRounding // false')"
disable_gaps="$(read_json '.optimization.toggles.disableGaps // false')"
disable_dim_inactive="$(read_json '.optimization.toggles.disableDimInactive // false')"

# If global optimization is enabled, enforce the strict performance preset.
if [[ "$opt_enabled" == "true" ]]; then
  hyprctl --batch "keyword animations:enabled 0;keyword decoration:blur:enabled 0;keyword decoration:shadow:enabled 0;keyword decoration:dim_inactive 0;keyword decoration:active_opacity 1.0;keyword decoration:inactive_opacity 1.0;keyword general:gaps_in 0;keyword general:gaps_out 0;keyword general:border_size 1;keyword decoration:rounding 0;keyword misc:vfr 0;keyword misc:vrr 2" >/dev/null 2>&1 || true
  exit 0
fi

# If no granular toggles are active, do nothing to avoid overriding user defaults.
if [[ "$disable_borders" != "true" && "$disable_transparency" != "true" && "$disable_animations" != "true" && "$disable_blur" != "true" && "$disable_shadows" != "true" && "$disable_rounding" != "true" && "$disable_gaps" != "true" && "$disable_dim_inactive" != "true" ]]; then
  exit 0
fi

animations_enabled=$((1 - $(as_int "$disable_animations")))
blur_enabled=$((1 - $(as_int "$disable_blur")))
shadow_enabled=$((1 - $(as_int "$disable_shadows")))
dim_inactive=$((1 - $(as_int "$disable_dim_inactive")))
inactive_opacity="0.9"
[[ "$disable_transparency" == "true" ]] && inactive_opacity="1.0"
gaps_in="2"
gaps_out="4"
[[ "$disable_gaps" == "true" ]] && gaps_in="0" && gaps_out="0"
border_size="2"
[[ "$disable_borders" == "true" ]] && border_size="0"
rounding="10"
[[ "$disable_rounding" == "true" ]] && rounding="0"

hyprctl --batch "keyword animations:enabled $animations_enabled;keyword decoration:blur:enabled $blur_enabled;keyword decoration:shadow:enabled $shadow_enabled;keyword decoration:dim_inactive $dim_inactive;keyword decoration:active_opacity 1.0;keyword decoration:inactive_opacity $inactive_opacity;keyword general:gaps_in $gaps_in;keyword general:gaps_out $gaps_out;keyword general:border_size $border_size;keyword decoration:rounding $rounding" >/dev/null 2>&1 || true

# Sincronizar transparencia con kitty
KITTY_CONF="$HOME/.config/kitty/kitty.conf"
if [[ -f "$KITTY_CONF" ]]; then
  if [[ "$disable_transparency" == "true" ]]; then
    sed -i 's/^background_opacity .*/background_opacity 1/' "$KITTY_CONF" 2>/dev/null || true
  else
    sed -i 's/^background_opacity .*/background_opacity 0.9/' "$KITTY_CONF" 2>/dev/null || true
  fi
  pkill -USR1 kitty 2>/dev/null || true
fi
