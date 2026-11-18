#!/usr/bin/env bash
# Converts everything in godot/assets/audio_incoming/ to ogg in godot/assets/audio/ (needs ffmpeg).
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
in="$root/godot/assets/audio_incoming"; out="$root/godot/assets/audio"
valid=$(grep -oE '^\| [^|]+\| [^|]+\| [a-z_]+ ' "$root/docs/audio/SOUND_LIST.md" | awk -F'|' '{gsub(/ /,"",$4); print $4}')
mkdir -p "$out"
for f in "$in"/*; do
  base="$(basename "$f")"; name="${base%.*}"
  case "$base" in README.md|.gitkeep) continue;; esac
  if ! grep -qx "$name" <<<"$valid"; then echo "skip $base (not in SOUND_LIST.md)"; continue; fi
  ffmpeg -y -loglevel error -i "$f" -ac 2 -c:a libvorbis -q:a 4 "$out/$name.ogg" && echo "ok $name.ogg"
done
echo "Remember to add each file to CREDITS.md"
