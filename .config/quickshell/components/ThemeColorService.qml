import QtQuick
import "./skwd-wall/qml"

QtObject {
  id: svc

  // Base dynamic palette (matugen/colors.json)
  property var colors

  // Optional override set from wallpaper config (e.g. #000000)
  readonly property string customFilterBarBgRaw: (Config.wallpaperFilterBarBgColor || "").trim()
  readonly property bool hasCustomFilterBarBg: customFilterBarBgRaw.length > 0

  readonly property color defaultFilterBarBg: colors
    ? Qt.rgba(colors.surfaceContainer.r, colors.surfaceContainer.g, colors.surfaceContainer.b, 0.85)
    : Qt.rgba(0.1, 0.12, 0.18, 0.85)

  // Shared background color for chip/filter bars across components.
  readonly property color filterBarBg: hasCustomFilterBarBg ? customFilterBarBgRaw : defaultFilterBarBg

  readonly property real _filterBarLuma: (filterBarBg.r * 0.2126) + (filterBarBg.g * 0.7152) + (filterBarBg.b * 0.0722)
  readonly property real _filterBarAlpha: filterBarBg.a > 0 ? filterBarBg.a : 1.0

  // Active chip color keeps contrast when the base override is very dark/light.
  readonly property color filterBarActiveBg: hasCustomFilterBarBg
    ? (_filterBarLuma < 0.08
      ? Qt.rgba(0.84, 0.84, 0.84, _filterBarAlpha)
      : (_filterBarLuma > 0.92
        ? Qt.rgba(0.24, 0.24, 0.24, _filterBarAlpha)
        : (_filterBarLuma < 0.45 ? Qt.lighter(filterBarBg, 1.45) : Qt.darker(filterBarBg, 1.55))))
    : (colors ? colors.primary : "#4fc3f7")

  readonly property real _activeLuma: (filterBarActiveBg.r * 0.2126) + (filterBarActiveBg.g * 0.7152) + (filterBarActiveBg.b * 0.0722)
  readonly property color filterBarActiveText: _activeLuma > 0.55 ? "#111111" : "#f5f5f5"
}