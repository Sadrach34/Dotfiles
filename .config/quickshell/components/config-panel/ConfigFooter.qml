import QtQuick
import "../skwd-wall/qml"

Rectangle {
  id: root
  property var panel
  property var colors

  anchors.bottom: parent.bottom
  anchors.left: parent.left
  anchors.right: parent.right
  height: 52
  color: "transparent"

  Rectangle {
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: 20
    anchors.rightMargin: 20
    height: 1
    color: root.colors ? Qt.rgba(root.colors.primary.r, root.colors.primary.g, root.colors.primary.b, 0.15) : Qt.rgba(1, 1, 1, 0.1)
  }

  Row {
    anchors.right: parent.right
    anchors.rightMargin: 20
    anchors.verticalCenter: parent.verticalCenter
    spacing: 10

    Rectangle {
      width: 110
      height: 32
      radius: 8
      color: defaultsMouse.containsMouse
        ? (root.colors ? Qt.rgba(root.colors.tertiary.r, root.colors.tertiary.g, root.colors.tertiary.b, 0.22) : Qt.rgba(0.5, 0.8, 1, 0.22))
        : "transparent"
      border.width: 1
      border.color: root.colors ? Qt.rgba(root.colors.tertiary.r, root.colors.tertiary.g, root.colors.tertiary.b, 0.50) : Qt.rgba(0.5, 0.8, 1, 0.50)

      Behavior on color { ColorAnimation { duration: 120 } }

      Text {
        anchors.centerIn: parent
        text: "DEFAULTS"
        font.family: Style.fontFamily
        font.pixelSize: 11
        font.weight: Font.Bold
        font.letterSpacing: 0.5
        color: root.colors ? root.colors.tertiary : "#8bceff"
      }

      MouseArea {
        id: defaultsMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.panel.resetToDefaultsDraft()
      }
    }

    Rectangle {
      width: 110
      height: 32
      radius: 8
      opacity: root.panel.hasUnsavedChanges ? 1 : 0.35
      color: discardMouse.containsMouse
        ? (root.colors ? Qt.rgba(root.colors.error.r, root.colors.error.g, root.colors.error.b, 0.22) : Qt.rgba(1, 0.3, 0.3, 0.22))
        : "transparent"
      border.width: 1
      border.color: root.colors ? Qt.rgba(root.colors.error.r, root.colors.error.g, root.colors.error.b, 0.50) : Qt.rgba(1, 0.3, 0.3, 0.50)

      Behavior on color { ColorAnimation { duration: 120 } }

      Text {
        anchors.centerIn: parent
        text: "DISCARD"
        font.family: Style.fontFamily
        font.pixelSize: 11
        font.weight: Font.Bold
        font.letterSpacing: 0.5
        color: root.colors ? root.colors.error : "#ff6b6b"
      }

      MouseArea {
        id: discardMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.panel.hasUnsavedChanges ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
          if (root.panel.hasUnsavedChanges) root.panel.discardChanges()
        }
      }
    }

    Rectangle {
      width: 110
      height: 32
      radius: 8
      opacity: root.panel.hasUnsavedChanges ? 1 : 0.35
      color: saveMouse.containsMouse
        ? (root.colors ? root.colors.primary : "#4fc3f7")
        : (root.colors ? Qt.rgba(root.colors.primary.r, root.colors.primary.g, root.colors.primary.b, 0.18) : Qt.rgba(0.3, 0.8, 1, 0.18))
      border.width: 1
      border.color: root.colors ? Qt.rgba(root.colors.primary.r, root.colors.primary.g, root.colors.primary.b, 0.55) : Qt.rgba(0.3, 0.8, 1, 0.55)

      Behavior on color { ColorAnimation { duration: 120 } }

      Text {
        anchors.centerIn: parent
        text: "SAVE"
        font.family: Style.fontFamily
        font.pixelSize: 11
        font.weight: Font.Bold
        font.letterSpacing: 0.5
        color: saveMouse.containsMouse
          ? (root.colors ? root.colors.primaryText : "#000")
          : (root.colors ? root.colors.primary : "#4fc3f7")
      }

      MouseArea {
        id: saveMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.panel.hasUnsavedChanges ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
          if (root.panel.hasUnsavedChanges) root.panel.saveAll()
        }
      }
    }
  }
}
