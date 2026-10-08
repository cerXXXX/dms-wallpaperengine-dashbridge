#!/usr/bin/env bash
# Print the video file of a video-type Wallpaper Engine Workshop item, or nothing
# for scenes/web wallpapers (the DMS lock screen can only play plain videos).
# usage: lock-video.sh <workshop-id>
id=$1
for root in "$HOME/.local/share/Steam" "$HOME/.steam/steam" \
            "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam" \
            "$HOME/snap/steam/common/.local/share/Steam"; do
    dir="$root/steamapps/workshop/content/431960/$id"
    [ -f "$dir/project.json" ] || continue
    python3 -I - "$dir" <<'EOF'
import json, os, sys
d = sys.argv[1]
p = json.load(open(os.path.join(d, "project.json"), encoding="utf-8-sig"))
f = p.get("file") or ""
if str(p.get("type", "")).lower() == "video" and f and os.path.isfile(os.path.join(d, f)):
    print(os.path.realpath(os.path.join(d, f)))
EOF
    exit 0
done
