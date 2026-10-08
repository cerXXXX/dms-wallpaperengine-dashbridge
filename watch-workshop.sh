#!/usr/bin/env bash
# Print a line whenever Steam adds, updates or removes a Wallpaper Engine
# Workshop item, so the bridge can resync the gallery.
dirs=()
for root in "$HOME/.local/share/Steam" "$HOME/.steam/steam" \
            "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam" \
            "$HOME/snap/steam/common/.local/share/Steam"; do
    d="$root/steamapps/workshop/content/431960"
    [ -d "$d" ] && dirs+=("$(realpath "$d")")
done
[ ${#dirs[@]} -gt 0 ] || exit 1
mapfile -t dirs < <(printf '%s\n' "${dirs[@]}" | sort -u)
exec inotifywait -mrq -e close_write,create,moved_to,delete,moved_from --format '%e %w%f' "${dirs[@]}"
