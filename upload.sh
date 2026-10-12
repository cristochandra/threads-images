#!/usr/bin/env bash
# Publish one image and print the public URL for the Threads API.
#   ./upload.sh ~/flow-mcp-out/ChartTest/chart.png  [optional-name]
set -euo pipefail

REPO_DIR="$HOME/Projects/threads-images"
MAX_BYTES=8388608          # Threads' image limit is 8 MB
MIN_WIDTH=320              # Threads scales up below this
MAX_WIDTH=1440             # Threads scales down above this

die() { echo "ERROR: $*" >&2; exit 1; }

[ $# -ge 1 ] || die "usage: ./upload.sh <image-file> [name]"
SRC="$1"
[ -f "$SRC" ] || die "file not found: $SRC"

EXT_LOWER=$(echo "${SRC##*.}" | tr '[:upper:]' '[:lower:]')
case "$EXT_LOWER" in
  png|jpg|jpeg) ;;
  *) die "Threads only accepts PNG or JPEG (got .$EXT_LOWER)" ;;
esac

BYTES=$(wc -c < "$SRC" | tr -d ' ')
[ "$BYTES" -le "$MAX_BYTES" ] || die "file is $((BYTES/1024/1024))MB, over the 8MB limit"

WIDTH=$(sips -g pixelWidth "$SRC" 2>/dev/null | awk '/pixelWidth/{print $2}')
if [ -n "${WIDTH:-}" ]; then
  [ "$WIDTH" -ge "$MIN_WIDTH" ] || echo "WARNING: width ${WIDTH}px is under ${MIN_WIDTH}px; Threads will scale it up."
  [ "$WIDTH" -le "$MAX_WIDTH" ] || echo "WARNING: width ${WIDTH}px is over ${MAX_WIDTH}px; Threads will scale it down."
fi

NAME="${2:-$(basename "${SRC%.*}")}"
SAFE=$(echo "$NAME" | tr ' ' '-' | tr -cd '[:alnum:]._-')
DEST="charts/$(date +%Y-%m-%d)-${SAFE}.${EXT_LOWER}"

cd "$REPO_DIR"

# Re-encode through PIL rather than copying. This strips EXIF, which on a phone
# photo can carry GPS coordinates - i.e. where you live - into a public repo.
python3 - "$SRC" "$DEST" <<'PY'
import sys
from PIL import Image

source, dest = sys.argv[1], sys.argv[2]
with Image.open(source) as img:
    clean = Image.new(img.mode, img.size)
    clean.putdata(list(img.getdata()))
    clean.save(dest)
print(f"stripped metadata -> {dest}")
PY

# Commit ONLY this path. Scoping it here means anything else left staged in this
# repo cannot ride along into a public commit.
git add -- "$DEST"
git commit -q -m "add $DEST" -- "$DEST"
git push -q origin main

SLUG=$(git config --get remote.origin.url | sed -E 's#.*github.com[:/]##; s#\.git$##')
echo
echo "Public URL:"
echo "https://raw.githubusercontent.com/${SLUG}/main/${DEST}"
