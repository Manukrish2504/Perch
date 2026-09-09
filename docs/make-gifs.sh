#!/bin/bash
# Regenerates the mascot GIFs in docs/mascot/.
#
# The frames come from the app itself, so the GIFs always match the shipped
# animations rather than drifting from them:
#
#   ./build.sh
#   ./docs/make-gifs.sh
#
# Requires ffmpeg (brew install ffmpeg).
set -euo pipefail
cd "$(dirname "$0")/.."

FRAMES="${TMPDIR:-/tmp}/perch-mascot-frames"
OUT="docs/mascot"
FPS=24

rm -rf "$FRAMES"; mkdir -p "$FRAMES" "$OUT"
echo "→ rendering frames"
PERCH_RENDER_MASCOT="$FRAMES" ./build/Perch.app/Contents/MacOS/Perch 2>/dev/null

echo "→ encoding gifs"
for dir in "$FRAMES"/*/; do
  name=$(basename "$dir")
  if [ "$name" = "hero" ]; then
    # The banner is keyed transparent so it sits on either GitHub theme. GIF
    # alpha is 1-bit, so the threshold decides per pixel; the mascot and the
    # wordmark are fully opaque, and only the ground shadow falls below it.
    ffmpeg -y -loglevel error -framerate $FPS -i "$dir/%03d.png" \
      -vf "fps=$FPS,scale=820:-1:flags=neighbor,split[a][b];[a]palettegen=max_colors=64:reserve_transparent=1[p];[b][p]paletteuse=dither=none:alpha_threshold=128" \
      "$OUT/$name.gif"
  else
    # Flat-colour pixel art: a small palette with no dithering keeps edges crisp
    # and the files small.
    ffmpeg -y -loglevel error -framerate $FPS -i "$dir/%03d.png" \
      -vf "fps=$FPS,scale=300:-1:flags=neighbor,split[a][b];[a]palettegen=max_colors=48[p];[b][p]paletteuse=dither=none" \
      "$OUT/$name.gif"
  fi
  printf '   %-18s %s\n' "$name.gif" "$(du -h "$OUT/$name.gif" | cut -f1)"
done
echo "✓ wrote $OUT"
