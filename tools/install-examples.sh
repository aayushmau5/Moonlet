#!/bin/zsh
# Copies the example wallpapers, packs, and nature sounds into the Moonlet library.
# Anything already in the library is left alone, so local edits are never overwritten.
set -euo pipefail

examples="${1:-examples}"
sounds="${2:-build/sounds}"
library="${MOONLET_LIBRARY:-$HOME/Moonlet}"

for kind in wallpapers packs; do
  [[ -d "$examples/$kind" ]] || continue
  mkdir -p "$library/$kind"
  for item in "$examples/$kind"/*(N); do
    name="${item:t}"
    if [[ -e "$library/$kind/$name" ]]; then
      echo "skip   $kind/$name (already in the library)"
      continue
    fi
    cp -R "$item" "$library/$kind/$name"
    if [[ "$kind" == wallpapers ]]; then
      soundtrack=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('soundtrack', ''))" "$item/wallpaper.json")
      if [[ -n "$soundtrack" && "$soundtrack" != video && -f "$sounds/$soundtrack" ]]; then
        cp "$sounds/$soundtrack" "$library/$kind/$name/"
      fi
    fi
    echo "added  $kind/$name"
  done
done

playlist="$library/music/Nature"
mkdir -p "$playlist"
typeset -A titles=(rain "Rain" waves "Ocean Waves" stream "Stream" wind "Wind" fire "Campfire")
for sound title in ${(kv)titles}; do
  if [[ -f "$sounds/$sound.m4a" && ! -e "$playlist/$title.m4a" ]]; then
    cp "$sounds/$sound.m4a" "$playlist/$title.m4a"
    echo "added  music/Nature/$title.m4a"
  fi
done
