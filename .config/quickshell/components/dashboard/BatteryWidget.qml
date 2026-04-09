import Quickshell.Io
import QtQuick
import QtQuick.Layouts

Rectangle {
    property var theme
    property bool dashboardVisible

    Layout.fillWidth: true
    Layout.preferredHeight: 55
    visible: hasBattery
    color: theme.surface
    radius: 15
    border.width: 1
    border.color: theme.border

    property bool hasBattery: false
    property int batteryVal: 0
    property string batteryStatus: "Unknown"

    function batteryIcon() {
        var st = (batteryStatus || "").toLowerCase()
        if (st.indexOf("charg") !== -1) return "󰂄"
        if (batteryVal >= 95) return "󰁹"
        if (batteryVal >= 80) return "󰂂"
        if (batteryVal >= 60) return "󰂀"
        if (batteryVal >= 40) return "󰁾"
        if (batteryVal >= 20) return "󰁻"
        return "󰁺"
    }

    function statusLabel() {
        var st = (batteryStatus || "").toLowerCase()
        if (st.indexOf("not charging") !== -1) return "Not charging"
        if (st.indexOf("charg") !== -1) return "Charging"
        if (st.indexOf("full") !== -1) return "Full"
        return "Discharging"
    }

    Timer {
        interval: 5000
        running: dashboardVisible
        repeat: true
        triggeredOnStart: true
        onTriggered: { if (!batProc.running) batProc.running = true }
    }

    Row {
        anchors.fill: parent
        anchors.margins: 15
        spacing: 10

        Text {
            width: 25; height: 24
            text: batteryIcon()
            color: batteryVal <= 15 ? "#f38ba8" : theme.accent
            font.pixelSize: 18
            font.family: "JetBrainsMono Nerd Font"
            verticalAlignment: Text.AlignVCenter
        }

        Rectangle {
            width: parent.width - 120
            height: 8
            anchors.verticalCenter: parent.verticalCenter
            radius: 4
            color: theme.border

            Rectangle {
                width: Math.max(0, parent.width * batteryVal / 100)
                height: parent.height
                radius: 4
                color: batteryVal <= 15 ? "#f38ba8" : theme.accent
                Behavior on width { NumberAnimation { duration: 120 } }
            }
        }

        Text {
            width: 70
            text: batteryVal + "%"
            color: theme.text
            font.pixelSize: 11
            font.family: "JetBrainsMono Nerd Font"
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
        }

        Text {
            width: 95
            text: statusLabel()
            color: theme.subtext
            font.pixelSize: 10
            font.family: "JetBrainsMono Nerd Font"
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
        }
    }

    Process {
        id: batProc
        command: ["bash", "-c", "BAT=''; for P in /sys/class/power_supply/*; do [ -d \"$P\" ] || continue; T=$(cat \"$P/type\" 2>/dev/null || true); [ \"${T,,}\" = battery ] || continue; BAT=\"$P\"; break; done; if [ -z \"$BAT\" ]; then echo 'none|0|Unknown'; exit 0; fi; if [ -f \"$BAT/capacity\" ]; then CAP=$(cat \"$BAT/capacity\" 2>/dev/null || echo 0); elif [ -f \"$BAT/energy_now\" ] && [ -f \"$BAT/energy_full\" ]; then NOW=$(cat \"$BAT/energy_now\" 2>/dev/null || echo 0); FULL=$(cat \"$BAT/energy_full\" 2>/dev/null || echo 0); if [ \"$FULL\" -gt 0 ] 2>/dev/null; then CAP=$(( NOW * 100 / FULL )); else CAP=0; fi; elif [ -f \"$BAT/charge_now\" ] && [ -f \"$BAT/charge_full\" ]; then NOW=$(cat \"$BAT/charge_now\" 2>/dev/null || echo 0); FULL=$(cat \"$BAT/charge_full\" 2>/dev/null || echo 0); if [ \"$FULL\" -gt 0 ] 2>/dev/null; then CAP=$(( NOW * 100 / FULL )); else CAP=0; fi; else CAP=0; fi; ST=$(cat \"$BAT/status\" 2>/dev/null || echo Unknown); echo \"yes|$CAP|$ST\""]
        stdout: SplitParser {
            onRead: data => {
                var p = data.trim().split("|")
                if (p.length >= 3) {
                    hasBattery = p[0] === "yes"
                    batteryVal = parseInt(p[1]) || 0
                    batteryStatus = p[2]
                }
            }
        }
    }
}
