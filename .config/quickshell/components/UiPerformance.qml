import Quickshell
import Quickshell.Io
import QtQuick

QtObject {
    id: uiPerf

    property string configPath: Quickshell.env("HOME") + "/.config/quickshell/data/config.json"
    property bool optimizationEnabled: false
    property bool disableQuickshellAnimations: false

    readonly property bool liteMode: optimizationEnabled || disableQuickshellAnimations

    function ms(value) {
        return liteMode ? 0 : value
    }

    function radius(normalValue, liteValue) {
        return liteMode ? liteValue : normalValue
    }

    function _reload() {
        var raw = configFile.text().trim()
        if (!raw) {
            optimizationEnabled = false
            disableQuickshellAnimations = false
            return
        }
        try {
            var cfg = JSON.parse(raw)
            var optimization = cfg && cfg.optimization ? cfg.optimization : {}
            var toggles = optimization && optimization.toggles ? optimization.toggles : {}
            optimizationEnabled = optimization.enabled === true
            disableQuickshellAnimations = toggles.disableQuickshellAnimations === true
        } catch (e) {
            optimizationEnabled = false
            disableQuickshellAnimations = false
        }
    }

    property FileView configFile: FileView {
        path: uiPerf.configPath
        preload: true
        watchChanges: true
        onFileChanged: {
            uiPerf.configFile.reload()
            uiPerf._reload()
        }
    }

    Component.onCompleted: uiPerf._reload()
}
