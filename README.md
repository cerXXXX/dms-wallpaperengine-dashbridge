# Wallpaper Engine in DankDash

A [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) daemon plugin that puts your whole
Steam Workshop Wallpaper Engine library into the regular DMS wallpaper picker (the **Wallpapers** tab of the
dashboard that opens from the bar clock), and plays the picked wallpaper with
[linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine).

It sits on top of the [Linux Wallpaper Engine](https://github.com/sgtaziz/dms-wallpaperengine) DMS plugin,
which does the actual process management, and adds:

- **Workshop library in the dashboard picker.** Every subscribed Workshop item gets a preview in the folder the
  picker browses. Picking one switches the engine to that wallpaper.
- **Live library sync.** New subscriptions show up a few seconds after Steam finishes downloading them;
  unsubscribed items disappear.
- **No DMS wallpaper on top of the engine.** DMS draws its own wallpaper on the same layer-shell layer as the
  engine and can end up stacked above it, showing a static (and, before a screenshot exists, upscaled) image.
  The plugin hides the DMS wallpaper on screens the engine owns and restores your setting when you go back to
  a plain image or turn the engine off.
- **Video wallpapers on the lock screen.** For video-type wallpapers the lock screen plays the same video, using
  the DMS video screensaver. Scenes keep a static frame. Your own lock settings are restored for scenes and
  plain images.

## Requirements

- DankMaterialShell with the [Linux Wallpaper Engine](https://github.com/sgtaziz/dms-wallpaperengine) plugin
  installed and enabled
- [linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine) and Wallpaper Engine itself
  installed through Steam (for its assets)
- `imagemagick` (`magick`), `inotify-tools` (`inotifywait`), `python3`
- QtMultimedia (`qt6-multimedia` with the FFmpeg backend) for the lock screen video

## Installation

```sh
git clone https://github.com/cerXXXX/dms-wallpaperengine-dashbridge \
    ~/.config/DankMaterialShell/plugins/weDashBridge
dms ipc call plugins enable weDashBridge
```

Then:

1. In the Linux Wallpaper Engine plugin settings, pick any wallpaper once (so the current DMS wallpaper lives
   in the plugin's screenshot folder) and enable **Generate static wallpaper**. Without it the picker
   thumbnails, theme colors and the lock screen use the small Workshop preview instead of a real frame.
2. On niri, keep the engine out of the overview workspace cards:

   ```kdl
   layer-rule {
       match namespace="^linux-wallpaperengine$"
       place-within-backdrop true
   }
   ```

## How it works

The Linux Wallpaper Engine plugin sets the DMS wallpaper to a screenshot of the running scene,
`~/.cache/DankMaterialShell/we_screenshots/<monitor>-<workshopId>.jpg`, and the dashboard picker always browses
the folder of the current wallpaper. This plugin fills that folder with previews of every Workshop item under
the same names. When the picker selects one, the plugin calls
`dms ipc call linuxWallpaperEngine set <workshopId> <monitor>`, and the engine plugin then overwrites the preview
with a real screenshot.

## Limitations

- The picker shows one folder at a time, so while a Wallpaper Engine wallpaper is active your regular image
  folder is not listed. Choose a plain image from Settings → Wallpaper to switch back.
- With several monitors each wallpaper appears once per monitor.
- Only video wallpapers animate on the lock screen; the lock screen cannot host the engine itself.
- If you switch to a plain image, the engine keeps running underneath until you turn it off
  (`dms ipc call plugins toggle linuxWallpaperEngine`).

## License

MIT
