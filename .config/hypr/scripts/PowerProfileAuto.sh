#!/usr/bin/env bash
# Apply power profile automatically based on device type + config overrides.

set -u

CONFIG_FILE="$HOME/.config/quickshell/data/config.json"
DEVICE_TYPE="auto"
PROFILE_OVERRIDE=""

if command -v jq >/dev/null 2>&1 && [[ -f "$CONFIG_FILE" ]]; then
  DEVICE_TYPE="$(jq -r '.power.deviceType // "auto"' "$CONFIG_FILE" 2>/dev/null || echo auto)"
  PROFILE_OVERRIDE="$(jq -r '.power.profile // ""' "$CONFIG_FILE" 2>/dev/null || echo "")"
fi

IS_LAPTOP=0
case "$DEVICE_TYPE" in
  laptop) IS_LAPTOP=1 ;;
  desktop) IS_LAPTOP=0 ;;
  *) IS_LAPTOP=0 ;;
esac

TARGET_PROFILE="performance"
if [[ "$IS_LAPTOP" -eq 1 ]]; then
  case "$PROFILE_OVERRIDE" in
    power-saver|balanced|performance)
      TARGET_PROFILE="$PROFILE_OVERRIDE"
      ;;
    *)
      TARGET_PROFILE="balanced"
      ;;
  esac
fi

if ! command -v powerprofilesctl >/dev/null 2>&1; then
  exit 0
fi

powerprofilesctl set "$TARGET_PROFILE" >/dev/null 2>&1 || true
