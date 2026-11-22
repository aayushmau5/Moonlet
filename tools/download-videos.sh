#!/bin/zsh
# Downloads the video wallpapers listed in examples/videos.tsv into the Moonlet library.
set -euo pipefail

list="${1:-examples/videos.tsv}"
sounds="${2:-build/sounds}"
library="${MOONLET_LIBRARY:-$HOME/Moonlet}"
mkdir -p "$library/wallpapers"

while IFS=$'\t' read -r folder name url soundtrack; do
  [[ -z "$folder" || "$folder" == \#* ]] && continue
  destination="$library/wallpapers/$folder"
  if [[ -e "$destination" ]]; then
    echo "skip   $folder (already in the library)"
    continue
  fi

  staging=$(mktemp -d)
  mkdir "$staging/$folder"
  echo "fetch  $folder"
  curl -fsSL --retry 2 -o "$staging/$folder/$folder.mp4" "$url"
  if ! ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$staging/$folder/$folder.mp4" > /dev/null; then
    echo "error  $folder is not a readable video, skipped"
    rm -rf "$staging"
    continue
  fi
  echo "loop   $folder"
  "${0:a:h}/loop-video.sh" "$staging/$folder/$folder.mp4"
  if [[ -n "${soundtrack:-}" && -f "$sounds/$soundtrack.m4a" ]]; then
    cp "$sounds/$soundtrack.m4a" "$staging/$folder/"
    printf '{\n  "name": "%s",\n  "type": "video",\n  "source": "%s.mp4",\n  "soundtrack": "%s.m4a",\n  "volume": 0.8\n}\n' "$name" "$folder" "$soundtrack" > "$staging/$folder/wallpaper.json"
  else
    printf '{\n  "name": "%s",\n  "type": "video",\n  "source": "%s.mp4"\n}\n' "$name" "$folder" > "$staging/$folder/wallpaper.json"
  fi
  mv "$staging/$folder" "$destination"
  rmdir "$staging"
  echo "added  $folder ($(du -h "$destination/$folder.mp4" | cut -f1))"
done < "$list"
