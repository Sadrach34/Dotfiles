import Quickshell
import QtQuick
import "./ModernClockWidget"

Variants {
    model: Quickshell.screens
    Loader {
        required property ShellScreen modelData
        active: true
        sourceComponent: Clock {
            targetScreen: modelData
        }
    }
}
