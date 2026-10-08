import QtCore
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Plugins

// Bridges the DankDash wallpaper tab to the linuxWallpaperEngine plugin.
// That plugin sets the DMS wallpaper to <shotDir>/<monitor>-<sceneId>.jpg, so the
// tab browses <shotDir>. We fill <shotDir> with Workshop previews under the same
// names; when the tab picks one, we tell the engine plugin to play that scene.
PluginComponent {
    id: root

    readonly property string shotDir: Paths.strip(StandardPaths.writableLocation(StandardPaths.GenericCacheLocation)) + "/DankMaterialShell/we_screenshots"
    readonly property string syncScript: Paths.strip(Qt.resolvedUrl("sync-gallery.sh"))
    property var pending: ({})
    property bool resyncPending: false
    property bool lockPatched: false

    function screenNames() {
        return Quickshell.screens.map(s => s.name)
    }

    // "<shotDir>/eDP-1-2511025691.jpg" -> { monitor: "eDP-1", id: "2511025691" }
    function parseShot(path) {
        if (!path || !path.startsWith(shotDir + "/"))
            return null
        const m = path.substring(shotDir.length + 1).match(/^(.+)-(\d+)\.jpg$/)
        if (!m || m[1].startsWith("span-"))
            return null
        return { monitor: m[1], id: m[2] }
    }

    function collectPicks() {
        const picks = {}
        if (SessionData.perMonitorWallpaper) {
            for (const name of screenNames()) {
                const shot = parseShot(SessionData.getMonitorWallpaper(name))
                if (shot && shot.monitor === name)
                    picks[name] = shot.id
            }
        } else {
            const shot = parseShot(SessionData.wallpaperPath)
            if (shot)
                picks[shot.monitor] = shot.id
        }
        pending = picks
        applyTimer.restart()
        updateDmsWallpaper()
        updateLockVideo()
    }

    function wallpaperFor(name) {
        return SessionData.perMonitorWallpaper ? SessionData.getMonitorWallpaper(name) : SessionData.wallpaperPath
    }

    // DMS draws its own wallpaper on the same background layer as the engine, and
    // every remap of that surface stacks it above the engine. Hide it on screens
    // the engine owns; put the user's original preference back otherwise.
    function updateDmsWallpaper() {
        const engineOn = PluginService.isPluginLoaded("linuxWallpaperEngine")
        const hidden = engineOn ? screenNames().filter(name => parseShot(wallpaperFor(name)) !== null) : []
        const prefs = Object.assign({}, SettingsData.screenPreferences || {})
        const saved = pluginService.loadPluginData(pluginId, "savedWallpaperPrefs", null)

        if (hidden.length === 0) {
            if (!saved)
                return
            if (saved.value === null)
                delete prefs.wallpaper
            else
                prefs.wallpaper = saved.value
            SettingsData.set("screenPreferences", prefs)
            pluginService.savePluginData(pluginId, "savedWallpaperPrefs", null)
            return
        }

        const original = saved ? saved.value : (prefs.wallpaper === undefined ? null : prefs.wallpaper)
        if (!saved)
            pluginService.savePluginData(pluginId, "savedWallpaperPrefs", { value: original })

        const allowed = (!original || original.includes("all"))
            ? Quickshell.screens
            : Quickshell.screens.filter(s => SettingsData.isScreenInPreferences(s, original))
        const wanted = allowed.map(s => s.name).filter(name => !hidden.includes(name))
        if (JSON.stringify(prefs.wallpaper) === JSON.stringify(wanted))
            return
        prefs.wallpaper = wanted
        SettingsData.set("screenPreferences", prefs)
    }

    // The lock screen can't host the engine, but it can play the wallpaper's video.
    // If the DMS lock screen is patched to play videos as its wallpaper (marked with
    // lockVideoWallpaper), the video goes behind the clock and password field;
    // stock DMS gets the video screensaver instead.
    // Scenes and plain images restore the user's own lock settings.
    function updateLockVideo() {
        const engineOn = PluginService.isPluginLoaded("linuxWallpaperEngine")
        let sceneId = ""
        for (const name of screenNames()) {
            const shot = engineOn ? parseShot(wallpaperFor(name)) : null
            if (shot) {
                sceneId = shot.id
                break
            }
        }
        if (!sceneId) {
            applyLockVideo("")
            return
        }
        lockVideoProc.running = false
        lockVideoProc.command = ["bash", Paths.strip(Qt.resolvedUrl("lock-video.sh")), sceneId]
        lockVideoProc.running = true
    }

    function setLockSetting(key, value) {
        if (SettingsData[key] !== value)
            SettingsData.set(key, value)
    }

    function applyLockVideo(videoPath) {
        const saved = pluginService.loadPluginData(pluginId, "savedLockVideo", null)
        const original = saved ? {
            enabled: saved.enabled,
            path: saved.path,
            cycling: saved.cycling,
            wallpaper: saved.wallpaper !== undefined ? saved.wallpaper : ""
        } : {
            enabled: SettingsData.lockScreenVideoEnabled,
            path: SettingsData.lockScreenVideoPath,
            cycling: SettingsData.lockScreenVideoCycling,
            wallpaper: SettingsData.lockScreenWallpaperPath
        }

        if (!videoPath) {
            if (!saved)
                return
            setLockSetting("lockScreenVideoEnabled", original.enabled)
            setLockSetting("lockScreenVideoPath", original.path)
            setLockSetting("lockScreenVideoCycling", original.cycling)
            setLockSetting("lockScreenWallpaperPath", original.wallpaper)
            pluginService.savePluginData(pluginId, "savedLockVideo", null)
            return
        }

        if (!saved || saved.wallpaper === undefined)
            pluginService.savePluginData(pluginId, "savedLockVideo", original)

        if (lockPatched) {
            setLockSetting("lockScreenWallpaperPath", videoPath)
            setLockSetting("lockScreenVideoEnabled", original.enabled)
            setLockSetting("lockScreenVideoPath", original.path)
            setLockSetting("lockScreenVideoCycling", original.cycling)
        } else {
            setLockSetting("lockScreenWallpaperPath", original.wallpaper)
            setLockSetting("lockScreenVideoPath", videoPath)
            setLockSetting("lockScreenVideoEnabled", true)
            setLockSetting("lockScreenVideoCycling", false)
        }
    }

    function syncGallery() {
        if (syncProc.running) {
            resyncPending = true
            return
        }
        syncProc.command = ["bash", syncScript, shotDir].concat(screenNames())
        syncProc.running = true
    }

    Connections {
        target: SessionData
        function onWallpaperPathChanged() { root.collectPicks() }
        function onMonitorWallpapersChanged() { root.collectPicks() }
        function onPerMonitorWallpaperChanged() { root.collectPicks() }
    }

    Connections {
        target: Quickshell
        function onScreensChanged() {
            root.syncGallery()
            root.updateDmsWallpaper()
        }
    }

    Connections {
        target: PluginService
        function onPluginLoaded(pluginId) {
            if (pluginId === "linuxWallpaperEngine") {
                root.updateDmsWallpaper()
                root.updateLockVideo()
            }
        }
        function onPluginUnloaded(pluginId) {
            if (pluginId === "linuxWallpaperEngine") {
                root.updateDmsWallpaper()
                root.updateLockVideo()
            }
        }
    }

    // Both SessionData signals can fire for one pick; apply once they settle.
    Timer {
        id: applyTimer
        interval: 300
        onTriggered: {
            for (const monitor in root.pending) {
                const proc = applyComponent.createObject(root, { monitor: monitor, sceneId: root.pending[monitor] })
                proc.running = true
            }
            root.pending = {}
        }
    }

    // The engine plugin restarts on every `set`, even for the same scene, and it
    // writes its own screenshot back to the same path, so only call `set` when
    // the picked scene differs from what is already playing.
    Component {
        id: applyComponent
        Process {
            property string monitor
            property string sceneId
            command: ["bash", "-c",
                'cur=$(dms ipc call linuxWallpaperEngine list | awk -v m="$1" \'index($0, m ": ") == 1 { print $2 }\'); ' +
                '[ "$cur" = "$2" ] || dms ipc call linuxWallpaperEngine set "$2" "$1"',
                "_", monitor, sceneId]
            onExited: destroy()
        }
    }

    Process {
        id: lockPatchCheck
        command: ["grep", "-q", "lockVideoWallpaper", "/usr/share/quickshell/dms/Modules/Lock/LockScreenContent.qml"]
        onExited: exitCode => {
            root.lockPatched = exitCode === 0
            root.updateLockVideo()
        }
    }

    Process {
        id: lockVideoProc
        stdout: StdioCollector {
            onStreamFinished: root.applyLockVideo(text.trim())
        }
    }

    Process {
        id: syncProc
        onExited: {
            if (root.resyncPending) {
                root.resyncPending = false
                root.syncGallery()
            }
        }
    }

    // Pick up Workshop subscriptions as Steam downloads or removes them.
    Process {
        id: watchProc
        command: ["bash", Paths.strip(Qt.resolvedUrl("watch-workshop.sh"))]
        running: true
        stdout: SplitParser {
            onRead: syncDebounce.restart()
        }
        onExited: watchRestart.restart()
    }

    // A download fires a burst of events; sync once it goes quiet.
    Timer {
        id: syncDebounce
        interval: 3000
        onTriggered: root.syncGallery()
    }

    // inotifywait exits if the Workshop dir is missing or gets replaced.
    Timer {
        id: watchRestart
        interval: 30000
        onTriggered: {
            root.syncGallery()
            watchProc.running = true
        }
    }

    Component.onCompleted: {
        syncGallery()
        updateDmsWallpaper()
        lockPatchCheck.running = true
    }
}
