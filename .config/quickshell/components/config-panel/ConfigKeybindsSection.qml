import QtQuick
import Quickshell.Io
import "../skwd-wall/qml"

Column {
  id: root
  property var panel
  property var colors

  property string query: ""
  property string stateFilter: "all"
  property var allBinds: []
  property var filteredBinds: []
  property string errorText: ""
  property bool hasDirtyBinds: false

  property var _savedBinds: []
  property var _systemLines: []
  property var _userLines: []
  property bool _defaultsCaptured: false
  property var _defaultBinds: []
  property var _defaultSystemLines: []
  property var _defaultUserLines: []

  width: parent.width
  spacing: 8

  function _deepCopy(value) {
    return JSON.parse(JSON.stringify(value))
  }

  function _normalizeToken(token) {
    var value = String(token || "").trim().replace(/_/g, " ")
    if (!value) return ""

    var lower = value.toLowerCase()
    if (lower === "ctrl" || lower === "control") return "CTRL"
    if (lower === "alt" || lower === "mod1") return "ALT"
    if (lower === "shift") return "SHIFT"
    if (lower === "super" || lower === "mod4" || lower === "win") return "SUPER"
    if (lower === "caps" || lower === "caps lock") return "CAPS"

    if (/^f\d+$/i.test(value)) return value.toUpperCase()
    if (/^xf86/i.test(value)) return value
    if (/^[a-z]$/i.test(value)) return value.toUpperCase()

    return value.charAt(0).toUpperCase() + value.slice(1)
  }

  function _modTokens(value) {
    var raw = String(value || "").replace(/[,+]/g, " ").trim()
    if (!raw) return []

    var parts = raw.split(/\s+/)
    var tokens = []
    for (var i = 0; i < parts.length; i++) {
      var token = _normalizeToken(parts[i])
      if (token && tokens.indexOf(token) < 0) tokens.push(token)
    }

    var ordered = []
    var order = ["SUPER", "CTRL", "ALT", "SHIFT", "CAPS"]
    for (var j = 0; j < order.length; j++) {
      if (tokens.indexOf(order[j]) >= 0) ordered.push(order[j])
    }
    for (var k = 0; k < tokens.length; k++) {
      if (ordered.indexOf(tokens[k]) < 0) ordered.push(tokens[k])
    }
    return ordered
  }

  function _formatMods(value) {
    var numeric = Number(value)
    if (!isNaN(numeric) && String(value).trim() !== "") {
      var bitMap = [
        { bit: 1, name: "SHIFT" },
        { bit: 2, name: "CAPS" },
        { bit: 4, name: "CTRL" },
        { bit: 8, name: "ALT" },
        { bit: 16, name: "MOD2" },
        { bit: 32, name: "MOD3" },
        { bit: 64, name: "SUPER" },
        { bit: 128, name: "MOD5" }
      ]
      var tokens = []
      for (var i = 0; i < bitMap.length; i++) {
        if ((numeric & bitMap[i].bit) !== 0) tokens.push(bitMap[i].name)
      }
      return tokens.join(" + ")
    }

    var textTokens = _modTokens(value)
    return textTokens.length > 0 ? textTokens.join(" + ") : ""
  }

  function _modsForFile(value) {
    return _modTokens(value).join(" ")
  }

  function _formatKey(value) {
    var key = String(value || "").trim()
    if (!key) return ""

    var lower = key.toLowerCase()
    if (lower.indexOf("code:") === 0) {
      var code = parseInt(lower.split(":")[1], 10)
      var codeMap = {
        10: "1",
        11: "2",
        12: "3",
        13: "4",
        14: "5",
        15: "6",
        16: "7",
        17: "8",
        18: "9",
        19: "0"
      }
      return codeMap[code] || ("Code " + code)
    }

    if (lower === "return" || lower === "enter") return "Enter"
    if (lower === "space") return "Space"
    if (lower === "tab") return "Tab"
    if (lower === "escape" || lower === "esc") return "Esc"
    if (lower === "delete") return "Delete"
    if (lower === "backspace") return "Backspace"
    if (lower === "left") return "Left"
    if (lower === "right") return "Right"
    if (lower === "up") return "Up"
    if (lower === "down") return "Down"

    if (/^f\d+$/i.test(key)) return key.toUpperCase()
    if (/^xf86/i.test(key)) return key
    if (/^[a-z]$/i.test(key)) return key.toUpperCase()

    return key.charAt(0).toUpperCase() + key.slice(1)
  }

  function _keyForFile(value) {
    var key = String(value || "").trim()
    if (!key) return ""

    var lower = key.toLowerCase()
    if (lower === "enter") return "Return"
    if (lower === "esc") return "Escape"
    if (lower === "space") return "Space"
    if (lower === "backspace") return "Backspace"
    if (lower === "delete") return "Delete"
    if (lower === "left") return "left"
    if (lower === "right") return "right"
    if (lower === "up") return "up"
    if (lower === "down") return "down"

    return key
  }

  function _bindSignature(mods, key) {
    return _modTokens(mods).join("+") + "|" + _formatKey(key).toLowerCase()
  }

  function _autoDescription(dispatcher, arg) {
    var d = String(dispatcher || "").trim().toLowerCase()
    var a = String(arg || "").trim()

    if (!d) return "Atajo personalizado"
    if (d === "exec") {
      if (a.indexOf("$term") >= 0) return "Abrir terminal"
      if (a.indexOf("firefox") >= 0) return "Abrir Firefox"
      if (a.indexOf("waybar") >= 0) return "Acción de Waybar"
      if (a.indexOf("screenshot") >= 0 || a.indexOf("ScreenShot.sh") >= 0) return "Captura de pantalla"
      if (a.indexOf("windowswitcher") >= 0) return "Abrir selector de ventanas"
      if (a.indexOf("applauncher") >= 0) return "Abrir lanzador de apps"
      if (a.indexOf("config toggle") >= 0) return "Abrir panel de configuración"
      return "Ejecutar comando"
    }
    if (d === "killactive") return "Cerrar ventana activa"
    if (d === "workspace") return "Cambiar espacio de trabajo"
    if (d === "movetoworkspace") return "Mover ventana de espacio de trabajo"
    if (d === "movetoworkspacesilent") return "Mover ventana (silencioso)"
    if (d === "movefocus") return "Mover foco entre ventanas"
    if (d === "movewindow") return "Mover ventana"
    if (d === "layoutmsg") return "Cambiar ajuste de layout"
    if (d === "fullscreen") return "Alternar pantalla completa"
    if (d === "togglefloating") return "Alternar modo flotante"
    if (d === "togglespecialworkspace") return "Alternar workspace especial"
    if (d === "togglegroup") return "Alternar grupo"
    return "Acción " + dispatcher
  }

  function _rowText(row) {
    return (
      (row.enabled ? "enabled" : "disabled") + " " + row.source + " " + row.mods + " " + row.key + " " + row.dispatcher + " " + row.arg + " " + row.description + " " + row.type
    ).toLowerCase()
  }

  function _sortRows(rows) {
    return rows.slice(0).sort(function(a, b) {
      if (a.enabled !== b.enabled) return a.enabled ? -1 : 1
      return (a.order || 0) - (b.order || 0)
    })
  }

  function _applyFilter() {
    var q = query.trim().toLowerCase()
    filteredBinds = allBinds.filter(function(row) {
      var statePass = root.stateFilter === "all"
        || (root.stateFilter === "on" && row.enabled)
        || (root.stateFilter === "off" && !row.enabled)
      if (!statePass) return false
      if (!q) return true
      return _rowText(row).indexOf(q) >= 0
    })
  }

  function _splitSpec(spec) {
    var out = []
    var current = ""
    for (var i = 0; i < spec.length; i++) {
      var ch = spec[i]
      if (ch === "," && out.length < 3) {
        out.push(current.trim())
        current = ""
      } else {
        current += ch
      }
    }
    out.push(current.trim())
    return out
  }

  function _isBindLine(line) {
    var trimmed = String(line || "").trim()
    return /^(#\s*)?(bind[a-z]*)\s*=\s*/i.test(trimmed)
  }

  function _parseFile(text, sourceTag) {
    var parsed = []
    var lines = String(text || "").split(/\r?\n/)
    var order = 0

    for (var i = 0; i < lines.length; i++) {
      var original = lines[i]
      var trimmed = original.trim()
      if (!trimmed) continue

      var commented = false
      var parseLine = trimmed
      if (parseLine.startsWith("#")) {
        commented = true
        parseLine = parseLine.replace(/^#\s*/, "")
      }

      var match = parseLine.match(/^(bind[a-z]*)\s*=\s*(.+)$/i)
      if (!match) continue

      var bindType = match[1]
      var specPart = match[2]
      var description = ""
      var hashIndex = specPart.indexOf("#")
      if (hashIndex >= 0) {
        description = specPart.substring(hashIndex + 1).trim()
        specPart = specPart.substring(0, hashIndex).trim()
      }

      var parts = _splitSpec(specPart)
      if (parts.length < 3) continue

      var mods = parts[0]
      var key = parts[1]
      var dispatcher = parts[2]
      var arg = parts.length > 3 ? parts.slice(3).join(", ") : ""
      if (!description) description = _autoDescription(dispatcher, arg)

      parsed.push({
        uid: sourceTag + ":" + i,
        source: sourceTag,
        lineIndex: i,
        order: order++,
        enabled: !commented,
        type: bindType,
        mods: _formatMods(mods),
        key: _formatKey(key),
        dispatcher: dispatcher,
        arg: arg,
        description: description
      })
    }

    return {
      rows: parsed,
      lines: lines
    }
  }

  function _composeBindLine(row) {
    var mods = _modsForFile(row.mods)
    var key = _keyForFile(row.key)
    var dispatcher = String(row.dispatcher || "").trim()
    var arg = String(row.arg || "").trim()
    var description = String(row.description || "").trim()

    var line = row.type + " = " + mods + ", " + key + ", " + dispatcher
    if (arg) line += ", " + arg
    if (description) line += " # " + description
    if (!row.enabled) line = "# " + line
    return line
  }

  function _rebuildSourceLines(baseLines, sourceRows) {
    var keepLines = []
    for (var i = 0; i < baseLines.length; i++) {
      if (!_isBindLine(baseLines[i])) keepLines.push(baseLines[i])
    }

    var sortedRows = _sortRows(sourceRows)
    var bindLines = []
    for (var j = 0; j < sortedRows.length; j++) {
      bindLines.push(_composeBindLine(sortedRows[j]))
    }

    while (keepLines.length > 0 && keepLines[keepLines.length - 1].trim() === "") {
      keepLines.pop()
    }
    if (bindLines.length > 0 && keepLines.length > 0) keepLines.push("")

    return keepLines.concat(bindLines)
  }

  function _reloadFromFiles() {
    errorText = ""

    var systemText = keybindsFile.text()
    var userText = userKeybindsFile.text()

    var parsedSystem = _parseFile(systemText, "SYSTEM")
    var parsedUser = _parseFile(userText, "USER")

    _systemLines = parsedSystem.lines
    _userLines = parsedUser.lines

    var merged = _sortRows(parsedSystem.rows.concat(parsedUser.rows))
    allBinds = _deepCopy(merged)
    _savedBinds = _deepCopy(merged)
    hasDirtyBinds = false

    if (!_defaultsCaptured) {
      _defaultBinds = _deepCopy(merged)
      _defaultSystemLines = _deepCopy(parsedSystem.lines)
      _defaultUserLines = _deepCopy(parsedUser.lines)
      _defaultsCaptured = true
    }

    _applyFilter()
  }

  function _setDirty(value) {
    hasDirtyBinds = value
    if (value && panel) panel.hasUnsavedChanges = true
  }

  function _touchDirtyFromDiff() {
    _setDirty(JSON.stringify(allBinds) !== JSON.stringify(_savedBinds))
  }

  function _updateRow(uid, field, value) {
    var changed = false
    for (var i = 0; i < allBinds.length; i++) {
      if (allBinds[i].uid !== uid) continue

      if (field === "mods") {
        allBinds[i].mods = _formatMods(value)
      } else if (field === "key") {
        allBinds[i].key = _formatKey(value)
      } else if (field === "enabled") {
        allBinds[i].enabled = !!value
      } else {
        allBinds[i][field] = String(value || "")
      }

      changed = true
      break
    }

    if (!changed) return
    allBinds = _sortRows(allBinds)
    _touchDirtyFromDiff()
    _applyFilter()
  }

  function discardDraftChanges() {
    allBinds = _deepCopy(_savedBinds)
    hasDirtyBinds = false
    _applyFilter()
  }

  function resetToDefaultsDraft() {
    if (!_defaultsCaptured) return
    allBinds = _deepCopy(_defaultBinds)
    _setDirty(true)
    _applyFilter()
  }

  function saveDraftChanges() {
    if (!hasDirtyBinds) return true

    var systemRows = allBinds.filter(function(row) { return row.source === "SYSTEM" })
    var userRows = allBinds.filter(function(row) { return row.source === "USER" })

    var systemLines = _rebuildSourceLines(_systemLines, systemRows)
    var userLines = _rebuildSourceLines(_userLines, userRows)

    try {
      keybindsFile.setText(systemLines.join("\n").replace(/\n+$/g, "") + "\n")
      userKeybindsFile.setText(userLines.join("\n").replace(/\n+$/g, "") + "\n")
    } catch (e) {
      errorText = "No se pudieron guardar los keybinds"
      console.log("ConfigKeybindsSection: save failed", e)
      return false
    }

    _systemLines = systemLines
    _userLines = userLines
    _savedBinds = _deepCopy(_sortRows(allBinds))
    hasDirtyBinds = false
    return true
  }

  function captureDefaultsFromCurrent() {
    _defaultBinds = _deepCopy(_savedBinds)
    _defaultSystemLines = _deepCopy(_systemLines)
    _defaultUserLines = _deepCopy(_userLines)
    _defaultsCaptured = true
  }

  function _reload() {
    _reloadFromFiles()
  }

  function _open(path) {
    Qt.openUrlExternally("file://" + path)
  }

  onVisibleChanged: if (visible) _reload()

  FileView {
    id: keybindsFile
    path: root.panel ? (root.panel.homeDir + "/.config/hypr/configs/Keybinds.conf") : ""
    preload: true
    watchChanges: true
    onFileChanged: {
      keybindsFile.reload()
      if (!root.hasDirtyBinds) root._reloadFromFiles()
    }
  }

  FileView {
    id: userKeybindsFile
    path: root.panel ? (root.panel.homeDir + "/.config/hypr/UserConfigs/UserKeybinds.conf") : ""
    preload: true
    watchChanges: true
    onFileChanged: {
      userKeybindsFile.reload()
      if (!root.hasDirtyBinds) root._reloadFromFiles()
    }
  }

  ConfigSectionTitle { text: "HYPRLAND KEYBINDS"; colors: root.colors }

  Rectangle {
    width: parent.width
    height: filterRow.implicitHeight + 16
    radius: 8
    color: colors ? Qt.rgba(colors.surfaceContainer.r, colors.surfaceContainer.g, colors.surfaceContainer.b, 0.30) : Qt.rgba(0.12, 0.14, 0.20, 0.30)
    border.width: 1
    border.color: colors ? Qt.rgba(colors.primary.r, colors.primary.g, colors.primary.b, 0.10) : Qt.rgba(1, 1, 1, 0.07)

    Row {
      id: filterRow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: 10
      anchors.rightMargin: 10
      spacing: 10

      Rectangle {
        width: parent.width - 390
        height: 36
        radius: 8
        color: colors ? Qt.rgba(colors.surface.r, colors.surface.g, colors.surface.b, 0.55) : "#1d2129"
        border.width: 1
        border.color: colors ? Qt.rgba(colors.primary.r, colors.primary.g, colors.primary.b, 0.25) : Qt.rgba(1, 1, 1, 0.15)

        Row {
          anchors.fill: parent
          anchors.leftMargin: 10
          anchors.rightMargin: 10
          spacing: 8

          Text {
            text: "󰍉"
            font.family: Style.fontFamilyNerdIcons
            font.pixelSize: 14
            color: colors ? Qt.rgba(colors.surfaceText.r, colors.surfaceText.g, colors.surfaceText.b, 0.45) : "#888"
            anchors.verticalCenter: parent.verticalCenter
          }

          TextInput {
            id: keybindSearch
            width: parent.width - 30
            height: parent.height
            verticalAlignment: TextInput.AlignVCenter
            color: colors ? colors.surfaceText : "#dcdcdc"
            font.family: Style.fontFamily
            font.pixelSize: 12
            clip: true
            selectByMouse: true
            text: root.query
            onTextChanged: { root.query = text; root._applyFilter() }

            Text {
              anchors.fill: parent
              anchors.leftMargin: 2
              verticalAlignment: Text.AlignVCenter
              text: "super, shift, screenshot, wallpaper..."
              font.family: Style.fontFamily
              font.pixelSize: 12
              color: colors ? Qt.rgba(colors.surfaceText.r, colors.surfaceText.g, colors.surfaceText.b, 0.30) : "#555"
              visible: keybindSearch.text.length === 0
            }
          }
        }
      }

      Rectangle {
        width: 190
        height: 36
        radius: 8
        color: colors ? Qt.rgba(colors.surfaceContainer.r, colors.surfaceContainer.g, colors.surfaceContainer.b, 0.55) : "#2f3440"

        Row {
          anchors.centerIn: parent
          spacing: 4

          Rectangle {
            width: 56
            height: 26
            radius: 6
            color: root.stateFilter === "all"
              ? (colors ? Qt.rgba(colors.primary.r, colors.primary.g, colors.primary.b, 0.90) : "#4fc3f7")
              : "transparent"
            border.width: 1
            border.color: colors ? Qt.rgba(colors.primary.r, colors.primary.g, colors.primary.b, 0.40) : Qt.rgba(1, 1, 1, 0.2)

            Behavior on color { ColorAnimation { duration: 120 } }

            Text {
              anchors.centerIn: parent
              text: "ALL"
              font.family: Style.fontFamilyCode
              font.pixelSize: 10
              font.weight: root.stateFilter === "all" ? Font.Bold : Font.Normal
              color: root.stateFilter === "all"
                ? (colors ? colors.primaryText : "#101010")
                : (colors ? colors.surfaceText : "#dcdcdc")
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: { root.stateFilter = "all"; root._applyFilter() }
            }
          }

          Rectangle {
            width: 56
            height: 26
            radius: 6
            color: root.stateFilter === "on"
              ? (colors ? Qt.rgba(colors.primary.r, colors.primary.g, colors.primary.b, 0.90) : "#4fc3f7")
              : "transparent"
            border.width: 1
            border.color: colors ? Qt.rgba(colors.primary.r, colors.primary.g, colors.primary.b, 0.40) : Qt.rgba(1, 1, 1, 0.2)

            Behavior on color { ColorAnimation { duration: 120 } }

            Text {
              anchors.centerIn: parent
              text: "ON"
              font.family: Style.fontFamilyCode
              font.pixelSize: 10
              font.weight: root.stateFilter === "on" ? Font.Bold : Font.Normal
              color: root.stateFilter === "on"
                ? (colors ? colors.primaryText : "#101010")
                : (colors ? colors.surfaceText : "#dcdcdc")
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: { root.stateFilter = "on"; root._applyFilter() }
            }
          }

          Rectangle {
            width: 56
            height: 26
            radius: 6
            color: root.stateFilter === "off"
              ? (colors ? Qt.rgba(colors.primary.r, colors.primary.g, colors.primary.b, 0.90) : "#4fc3f7")
              : "transparent"
            border.width: 1
            border.color: colors ? Qt.rgba(colors.primary.r, colors.primary.g, colors.primary.b, 0.40) : Qt.rgba(1, 1, 1, 0.2)

            Behavior on color { ColorAnimation { duration: 120 } }

            Text {
              anchors.centerIn: parent
              text: "OFF"
              font.family: Style.fontFamilyCode
              font.pixelSize: 10
              font.weight: root.stateFilter === "off" ? Font.Bold : Font.Normal
              color: root.stateFilter === "off"
                ? (colors ? colors.primaryText : "#101010")
                : (colors ? colors.surfaceText : "#dcdcdc")
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: { root.stateFilter = "off"; root._applyFilter() }
            }
          }
        }
      }

      Rectangle {
        width: 100
        height: 36
        radius: 8
        color: refreshMouse.containsMouse
          ? (colors ? Qt.rgba(colors.primary.r, colors.primary.g, colors.primary.b, 0.22) : Qt.rgba(0.3, 0.8, 1, 0.22))
          : "transparent"
        border.width: 1
        border.color: colors ? Qt.rgba(colors.primary.r, colors.primary.g, colors.primary.b, 0.50) : Qt.rgba(0.3, 0.8, 1, 0.50)

        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
          anchors.centerIn: parent
          text: "REFRESH"
          font.family: Style.fontFamily
          font.pixelSize: 11
          font.weight: Font.Bold
          font.letterSpacing: 0.5
          color: colors ? colors.primary : "#4fc3f7"
        }

        MouseArea {
          id: refreshMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root._reload()
        }
      }

      Rectangle {
        width: 100
        height: 36
        radius: 8
        color: openFilesMouse.containsMouse
          ? (colors ? Qt.rgba(colors.surfaceVariant.r, colors.surfaceVariant.g, colors.surfaceVariant.b, 0.45) : Qt.rgba(1, 1, 1, 0.10))
          : "transparent"
        border.width: 1
        border.color: colors ? Qt.rgba(colors.surfaceText.r, colors.surfaceText.g, colors.surfaceText.b, 0.25) : Qt.rgba(1, 1, 1, 0.15)

        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
          anchors.centerIn: parent
          text: "OPEN FILES"
          font.family: Style.fontFamily
          font.pixelSize: 10
          font.weight: Font.Bold
          font.letterSpacing: 0.5
          color: colors ? Qt.rgba(colors.surfaceText.r, colors.surfaceText.g, colors.surfaceText.b, 0.75) : "#aaa"
        }

        MouseArea {
          id: openFilesMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            root._open(panel.homeDir + "/.config/hypr/configs/Keybinds.conf")
            root._open(panel.homeDir + "/.config/hypr/UserConfigs/UserKeybinds.conf")
          }
        }
      }
    }
  }

  Text {
    text: errorText !== "" ? errorText : ("Binds: " + filteredBinds.length + (hasDirtyBinds ? " (edited)" : ""))
    font.family: Style.fontFamily
    font.pixelSize: 11
    color: errorText !== ""
      ? (colors ? colors.error : "#ff6b6b")
      : (colors ? Qt.rgba(colors.surfaceText.r, colors.surfaceText.g, colors.surfaceText.b, 0.8) : "#cccccc")
  }

  Column {
    width: parent.width
    spacing: 4

    Rectangle {
      width: parent.width
      height: 28
      radius: 6
      color: colors ? Qt.rgba(colors.surfaceContainer.r, colors.surfaceContainer.g, colors.surfaceContainer.b, 0.7) : "#2f3440"

      Row {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 10

        Text {
          width: 70
          text: "FILE"
          font.family: Style.fontFamily
          font.pixelSize: 10
          font.weight: Font.Bold
          color: colors ? colors.tertiary : "#8bceff"
          verticalAlignment: Text.AlignVCenter
        }

        Text {
          width: 70
          text: "STATE"
          font.family: Style.fontFamily
          font.pixelSize: 10
          font.weight: Font.Bold
          color: colors ? colors.tertiary : "#8bceff"
          verticalAlignment: Text.AlignVCenter
        }

        Text {
          width: 170
          text: "MODS"
          font.family: Style.fontFamily
          font.pixelSize: 10
          font.weight: Font.Bold
          color: colors ? colors.tertiary : "#8bceff"
          verticalAlignment: Text.AlignVCenter
        }

        Text {
          width: 110
          text: "KEY"
          font.family: Style.fontFamily
          font.pixelSize: 10
          font.weight: Font.Bold
          color: colors ? colors.tertiary : "#8bceff"
          verticalAlignment: Text.AlignVCenter
        }

        Text {
          width: 180
          text: "ACTION"
          font.family: Style.fontFamily
          font.pixelSize: 10
          font.weight: Font.Bold
          color: colors ? colors.tertiary : "#8bceff"
          verticalAlignment: Text.AlignVCenter
        }

        Text {
          width: parent.width - 670
          text: "DESCRIPCIÓN"
          font.family: Style.fontFamily
          font.pixelSize: 10
          font.weight: Font.Bold
          color: colors ? colors.tertiary : "#8bceff"
          verticalAlignment: Text.AlignVCenter
        }

        Text {
          width: 60
          text: "TYPE"
          font.family: Style.fontFamily
          font.pixelSize: 10
          font.weight: Font.Bold
          color: colors ? colors.tertiary : "#8bceff"
          verticalAlignment: Text.AlignVCenter
        }
      }
    }

    Repeater {
      model: filteredBinds

      Rectangle {
        width: parent.width
        height: 36
        radius: 4
        color: index % 2 === 0
          ? (colors ? Qt.rgba(colors.surfaceContainer.r, colors.surfaceContainer.g, colors.surfaceContainer.b, 0.45) : "#252933")
          : (colors ? Qt.rgba(colors.surfaceContainer.r, colors.surfaceContainer.g, colors.surfaceContainer.b, 0.28) : "#20242d")

        Row {
          anchors.fill: parent
          anchors.leftMargin: 10
          anchors.rightMargin: 10
          spacing: 10

          Text {
            width: 70
            text: modelData.source
            font.family: Style.fontFamilyCode
            font.pixelSize: 10
            color: colors ? colors.tertiary : "#8bceff"
            verticalAlignment: Text.AlignVCenter
          }

          Rectangle {
            width: 70
            height: 24
            radius: 4
            color: modelData.enabled
              ? (colors ? Qt.rgba(colors.primary.r, colors.primary.g, colors.primary.b, 0.22) : Qt.rgba(0.3, 0.8, 1, 0.22))
              : (colors ? Qt.rgba(colors.error.r, colors.error.g, colors.error.b, 0.20) : Qt.rgba(1, 0.3, 0.3, 0.20))
            border.width: 1
            border.color: modelData.enabled
              ? (colors ? Qt.rgba(colors.primary.r, colors.primary.g, colors.primary.b, 0.45) : Qt.rgba(0.3, 0.8, 1, 0.45))
              : (colors ? Qt.rgba(colors.error.r, colors.error.g, colors.error.b, 0.45) : Qt.rgba(1, 0.3, 0.3, 0.45))

            Text {
              anchors.centerIn: parent
              text: modelData.enabled ? "ON" : "OFF"
              font.family: Style.fontFamilyCode
              font.pixelSize: 10
              color: colors ? colors.surfaceText : "#d9d9d9"
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root._updateRow(modelData.uid, "enabled", !modelData.enabled)
            }
          }

          Rectangle {
            width: 170
            height: 24
            radius: 4
            color: colors ? Qt.rgba(colors.surface.r, colors.surface.g, colors.surface.b, 0.35) : "#1d2129"
            border.width: 1
            border.color: colors ? Qt.rgba(colors.primary.r, colors.primary.g, colors.primary.b, 0.35) : Qt.rgba(1, 1, 1, 0.2)

            TextInput {
              anchors.fill: parent
              anchors.leftMargin: 8
              anchors.rightMargin: 8
              verticalAlignment: TextInput.AlignVCenter
              color: colors ? colors.surfaceText : "#d9d9d9"
              font.family: Style.fontFamilyCode
              font.pixelSize: 10
              clip: true
              text: modelData.mods
              selectByMouse: true
              onEditingFinished: root._updateRow(modelData.uid, "mods", text)
            }
          }

          Rectangle {
            width: 110
            height: 24
            radius: 4
            color: colors ? Qt.rgba(colors.surface.r, colors.surface.g, colors.surface.b, 0.35) : "#1d2129"
            border.width: 1
            border.color: colors ? Qt.rgba(colors.primary.r, colors.primary.g, colors.primary.b, 0.35) : Qt.rgba(1, 1, 1, 0.2)

            TextInput {
              anchors.fill: parent
              anchors.leftMargin: 8
              anchors.rightMargin: 8
              verticalAlignment: TextInput.AlignVCenter
              color: colors ? colors.surfaceText : "#d9d9d9"
              font.family: Style.fontFamilyCode
              font.pixelSize: 10
              clip: true
              text: modelData.key
              selectByMouse: true
              onEditingFinished: root._updateRow(modelData.uid, "key", text)
            }
          }

          Text {
            width: 180
            text: modelData.dispatcher + (modelData.arg ? (", " + modelData.arg) : "")
            font.family: Style.fontFamily
            font.pixelSize: 10
            color: colors ? colors.surfaceText : "#d9d9d9"
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
          }

          Rectangle {
            width: parent.width - 670
            height: 24
            radius: 4
            color: colors ? Qt.rgba(colors.surface.r, colors.surface.g, colors.surface.b, 0.35) : "#1d2129"
            border.width: 1
            border.color: colors ? Qt.rgba(colors.primary.r, colors.primary.g, colors.primary.b, 0.35) : Qt.rgba(1, 1, 1, 0.2)

            TextInput {
              anchors.fill: parent
              anchors.leftMargin: 8
              anchors.rightMargin: 8
              verticalAlignment: TextInput.AlignVCenter
              color: colors ? colors.surfaceText : "#d9d9d9"
              font.family: Style.fontFamily
              font.pixelSize: 10
              clip: true
              text: modelData.description
              selectByMouse: true
              onEditingFinished: root._updateRow(modelData.uid, "description", text)
            }
          }

          Text {
            width: 60
            text: modelData.type
            font.family: Style.fontFamilyCode
            font.pixelSize: 10
            color: colors ? colors.tertiary : "#8bceff"
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
          }
        }
      }
    }
  }
}
