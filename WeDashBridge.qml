import QtCore
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Plugins

// Bridges the DankDash wallpaper tab to the linuxWallpaperEngine plugin.
// The tab browses the folder of the current wallpaper, so the DMS wallpaper is
// kept on <galleryDir>/<sceneId>.jpg, a folder holding one preview per Workshop
// item; picking one there tells the engine plugin to play that scene.
// The engine plugin also sets the DMS wallpaper, to its screenshots in
// <shotDir>; those are never treated as picks, only folded back into the gallery.
PluginComponent {
    id: root

    readonly property string cacheDir: Paths.strip(StandardPaths.writableLocation(StandardPaths.GenericCacheLocation)) + "/DankMaterialShell"
    readonly property string galleryDir: cacheDir + "/we_gallery"
    readonly property string shotDir: cacheDir + "/we_screenshots"
    readonly property string syncScript: Paths.strip(Qt.resolvedUrl("sync-gallery.sh"))
    property bool resyncPending: false
    property bool lockPatched: false
    // monitor -> { id, time } of the last scene the bridge asked the engine for
    property var desired: ({})
    // monitor -> classified wallpaper waiting for a decision
    property var queued: ({})
    property bool decidePending: false

    function screenNames() {
        return Quickshell.screens.map(s => s.name)
    }

    function wallpaperFor(name) {
        return SessionData.perMonitorWallpaper ? SessionData.getMonitorWallpaper(name) : SessionData.wallpaperPath
    }

    function setWallpaperFor(name, path) {
        if (wallpaperFor(name) === path)
            return
        if (SessionData.perMonitorWallpaper)
            SessionData.setMonitorWallpaper(name, path)
        else
            SessionData.setWallpaper(path)
    }

    function galleryPath(sceneId) {
        return galleryDir + "/" + sceneId + ".jpg"
    }

    // "<galleryDir>/2511025691.jpg"       -> { kind: "pick", id: "2511025691" }
    // "<shotDir>/eDP-1-2511025691.jpg"    -> { kind: "shot", id: "2511025691" }
    function classify(path) {
        if (!path)
            return null
        if (path.startsWith(galleryDir + "/")) {
            const m = path.substring(galleryDir.length + 1).match(/^(\d+)\.jpg$/)
            return m ? { kind: "pick", id: m[1], path: path } : null
        }
        if (path.startsWith(shotDir + "/")) {
            const m = path.substring(shotDir.length + 1).match(/^(.+)-(\d+)\.jpg$/)
            return (m && !m[1].startsWith("span-")) ? { kind: "shot", id: m[2], path: path } : null
        }
        return null
    }

    function handleWallpaperChange(picksToo) {
        const next = Object.assign({}, queued)
        for (const name of screenNames()) {
            const c = classify(wallpaperFor(name))
            if (c && (picksToo || c.kind === "shot"))
                next[name] = c
        }
        queued = next
        decideTimer.restart()
        updateDmsWallpaper()
        updateLockVideo()
    }

    // cur: monitor -> scene the engine plugin reports as playing
    function decide(cur) {
        const now = Date.now()
        for (const name in queued) {
            const c = queued[name]
            const want = desired[name]
            const recent = want && now - want.time < 15000

            if (c.kind === "pick") {
                if (c.id === cur[name] || (recent && c.id === want.id))
                    continue
                desired = Object.assign({}, desired, { [name]: { id: c.id, time: now } })
                Quickshell.execDetached(["dms", "ipc", "call", "linuxWallpaperEngine", "set", c.id, name])
                continue
            }

            // The engine plugin's screenshot timers outlive scene switches, so a
            // screenshot may belong to a scene that is no longer playing. Never
            // switch on one: keep the wallpaper on the scene that should play.
            const target = recent ? want.id : cur[name]
            if (!target)
                continue
            if (c.id === target) {
                const adopt = adoptComponent.createObject(root, { monitor: name, sceneId: target, shot: c.path })
                adopt.running = true
            } else {
                setWallpaperFor(name, galleryPath(target))
            }
        }
        queued = {}
    }

    // DMS draws its own wallpaper on the same background layer as the engine, and
    // every remap of that surface stacks it above the engine. Hide it on screens
    // the engine owns; put the user's original preference back otherwise.
    function updateDmsWallpaper() {
        const engineOn = PluginService.isPluginLoaded("linuxWallpaperEngine")
        const hidden = engineOn ? screenNames().filter(name => classify(wallpaperFor(name)) !== null) : []
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
            const c = engineOn ? classify(wallpaperFor(name)) : null
            if (c) {
                sceneId = c.id
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
        syncProc.command = ["bash", syncScript, galleryDir]
        syncProc.running = true
    }

    Connections {
        target: SessionData
        function onWallpaperPathChanged() { root.handleWallpaperChange(true) }
        function onMonitorWallpapersChanged() { root.handleWallpaperChange(true) }
        function onPerMonitorWallpaperChanged() { root.handleWallpaperChange(true) }
    }

    Connections {
        target: Quickshell
        function onScreensChanged() { root.updateDmsWallpaper() }
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

    // Several SessionData signals fire for one change; decide once they settle,
    // against what the engine plugin says is playing right now.
    Timer {
        id: decideTimer
        interval: 300
        onTriggered: {
            if (listProc.running) {
                root.decidePending = true
                return
            }
            listProc.running = true
        }
    }

    Process {
        id: listProc
        command: ["dms", "ipc", "call", "linuxWallpaperEngine", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const cur = {}
                for (const line of text.split("\n")) {
                    const m = line.match(/^([^:\s]+): (\d+)/)
                    if (m)
                        cur[m[1]] = m[2]
                }
                root.decide(cur)
            }
        }
        onExited: {
            if (root.decidePending) {
                root.decidePending = false
                decideTimer.restart()
            }
        }
    }

    // Copy the engine's screenshot over the scene's gallery preview, then point
    // the wallpaper at the gallery entry so the tab keeps browsing the gallery.
    Component {
        id: adoptComponent
        Process {
            property string monitor
            property string sceneId
            property string shot
            command: ["bash", "-c", 'cp -f "$1" "$2.tmp" && mv -f "$2.tmp" "$2"', "_", shot, root.galleryPath(sceneId)]
            onExited: {
                root.setWallpaperFor(monitor, root.galleryPath(sceneId))
                destroy()
            }
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

    // Startup: fold a wallpaper left on an engine screenshot back into the gallery,
    // but don't treat whatever gallery entry is current as a fresh pick.
    Component.onCompleted: {
        syncGallery()
        updateDmsWallpaper()
        lockPatchCheck.running = true
        handleWallpaperChange(false)
    }
}
