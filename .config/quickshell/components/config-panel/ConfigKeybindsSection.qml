import QtQuick
import Quickshell.Io
import "../skwd-wall/qml"

Column {
  id: root
  property var panel
  property var colors

  property string query: ""
  property var allBinds: []
  property var filteredBinds: []
  property string errorText: ""

  width: parent.width
  spacing: 8

  function _rowText(row) {
    return (row.mods + " " + row.key + " " + row.action + " " + row.type).toLowerCase()
  }

  function _applyFilter() {
    var q = query.trim().toLowerCase()
    if (!q) {
      filteredBinds = allBinds
      return
    }
    filteredBinds = allBinds.filter(function(row) { return _rowText(row).indexOf(q) >= 0 })
  }

  function _reload() {
    errorText = ""
    bindProc.rawOut = ""
    bindProc.command = ["bash", "-lc", "hyprctl binds -j 2>/dev/null || echo '[]'"]
    bindProc.running = true
  }

  function _open(path) {
    Qt.openUrlExternally("file://" + path)
  }

  onVisibleChanged: if (visible) _reload()

  ConfigSectionTitle { text: "HYPRLAND KEYBINDS"; colors: root.colors }

  Row {
    width: parent.width
    spacing: 10

    ConfigTextField {
      width: parent.width - 230
      label: "Buscar"
      value: root.query
      placeholder: "super, shift, screenshot, wallpaper..."
      onEdited: v => { root.query = v; root._applyFilter() }
      colors: root.colors
    }

    Rectangle {
      width: 100
      height: 30
      radius: 6
      color: colors ? Qt.rgba(colors.primary.r, colors.primary.g, colors.primary.b, 0.9) : "#4fc3f7"

      Text {
        anchors.centerIn: parent
        text: "REFRESH"
        font.family: Style.fontFamily
        font.pixelSize: 11
        font.weight: Font.Bold
        color: colors ? colors.primaryText : "#101010"
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root._reload()
      }
    }

    Rectangle {
      width: 100
      height: 30
      radius: 6
      color: colors ? Qt.rgba(colors.surfaceContainer.r, colors.surfaceContainer.g, colors.surfaceContainer.b, 0.8) : "#2f3440"

      Text {
        anchors.centerIn: parent
        text: "OPEN FILES"
        font.family: Style.fontFamily
        font.pixelSize: 10
        font.weight: Font.Bold
        color: colors ? colors.surfaceText : "#dcdcdc"
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          root._open(panel.homeDir + "/.config/hypr/configs/Keybinds.conf")
          root._open(panel.homeDir + "/.config/hypr/UserConfigs/UserKeybinds.conf")
        }
      }
    }
  }

  Text {
    text: errorText !== "" ? errorText : ("Binds: " + filteredBinds.length)
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
          width: 180
          text: "MODS + KEY"
          font.family: Style.fontFamily
          font.pixelSize: 10
          font.weight: Font.Bold
          color: colors ? colors.tertiary : "#8bceff"
          verticalAlignment: Text.AlignVCenter
        }

        Text {
          width: parent.width - 320
          text: "ACTION"
          font.family: Style.fontFamily
          font.pixelSize: 10
          font.weight: Font.Bold
          color: colors ? colors.tertiary : "#8bceff"
          verticalAlignment: Text.AlignVCenter
        }

        Text {
          width: 100
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
        height: 28
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
            width: 180
            text: (modelData.mods ? modelData.mods + " + " : "") + modelData.key
            font.family: Style.fontFamilyCode
            font.pixelSize: 10
            color: colors ? colors.surfaceText : "#d9d9d9"
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
          }

          Text {
            width: parent.width - 320
            text: modelData.action
            font.family: Style.fontFamily
            font.pixelSize: 10
            color: colors ? colors.surfaceText : "#d9d9d9"
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
          }

          Text {
            width: 100
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

  Process {
    id: bindProc
    property string rawOut: ""
    command: ["bash", "-lc", "true"]

    stdout: SplitParser {
      splitMarker: ""
      onRead: data => bindProc.rawOut += data
    }

    onExited: {
      var parsed = []
      try {
        var data = JSON.parse(bindProc.rawOut.trim())
        if (!Array.isArray(data)) data = []

        for (var i = 0; i < data.length; i++) {
          var b = data[i]
          var mods = String(b.modmask || b.mods || b.mod || "").replace(/_/g, " ").trim()
          var key = String(b.key || b.keycode || "")
          var type = String(b.type || b.handler || "bind")
          var action = ""

          if (b.description) action = String(b.description)
          else {
            var dispatch = String(b.dispatcher || b.dispatch || "")
            var arg = String(b.arg || b.value || "")
            action = (dispatch + (arg ? (", " + arg) : "")).trim()
          }

          parsed.push({
            mods: mods,
            key: key,
            action: action,
            type: type
          })
        }
      } catch (e) {
        errorText = "No se pudieron leer binds con hyprctl (¿Hyprland activo?)"
        allBinds = []
        filteredBinds = []
        return
      }

      errorText = ""
      allBinds = parsed
      _applyFilter()
    }
  }
}
