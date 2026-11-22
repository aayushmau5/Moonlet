#!/bin/zsh
# Re-encodes a video so it loops without a visible jump: the last stretch
# cross-fades into the opening frames, so the final frame flows into the first.
set -euo pipefail

input="$1"
duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$input")
fade=$(python3 -c "print(min(1.5, $duration / 4))")
offset=$(python3 -c "print($duration - 2 * $fade)")
output="${input:r}.looping.mp4"

ffmpeg -loglevel error -y -i "$input" -filter_complex \
  "[0:v]trim=start=$fade,setpts=PTS-STARTPTS[main];[0:v]trim=end=$fade,setpts=PTS-STARTPTS[head];[main][head]xfade=transition=fade:duration=$fade:offset=$offset,format=yuv420p[out]" \
  -map "[out]" -an -c:v libx264 -preset medium -crf 20 -movflags +faststart "$output"
mv "$output" "$input"
