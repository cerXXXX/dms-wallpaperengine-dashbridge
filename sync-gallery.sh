#!/usr/bin/env bash
# Fill the linux-wallpaperengine plugin's screenshot dir with Workshop previews,
# named <monitor>-<id>.jpg exactly like the plugin's own screenshots, so the
# DankDash wallpaper tab lists the whole library.
# usage: sync-gallery.sh <screenshot-dir> <monitor>...
set -u
out=$1; shift
mkdir -p "$out"

declare -A seen
for root in "$HOME/.local/share/Steam" "$HOME/.steam/steam" \
            "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam" \
            "$HOME/snap/steam/common/.local/share/Steam"; do
    ws="$root/steamapps/workshop/content/431960"
    [ -d "$ws" ] || continue
    for dir in "$ws"/*/; do
        id=$(basename "$dir")
        [[ $id =~ ^[0-9]+$ ]] || continue
        [ -z "${seen[$id]:-}" ] || continue
        seen[$id]=1
        prev=$(ls "$dir"preview.* 2>/dev/null | head -n1)
        [ -n "$prev" ] || continue
        for mon in "$@"; do
            dst="$out/$mon-$id.jpg"
            [ -e "$dst" ] && continue
            tmp="$out/.$mon-$id.tmp.jpg"
            magick "${prev}[0]" -resize '1920x1080^' -gravity center -extent 1920x1080 \
                -quality 85 "$tmp" 2>/dev/null && mv -f "$tmp" "$dst"
            rm -f "$tmp"
        done
    done
done

# Drop entries for wallpapers that were unsubscribed in Steam.
[ ${#seen[@]} -gt 0 ] || exit 0
for f in "$out"/*.jpg; do
    [ -e "$f" ] || continue
    name=$(basename "$f" .jpg)
    id=${name##*-}
    [[ $id =~ ^[0-9]+$ ]] || continue
    [[ $name == span-* ]] && continue
    [ -n "${seen[$id]:-}" ] || rm -f "$f"
done
