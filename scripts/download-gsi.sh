#!/usr/bin/env bash
# Parallel ranged download for slow single-stream hosts (GitHub releases).
#
#   bash scripts/download-gsi.sh <url> <output> [connections=12]
#
set -uo pipefail

URL=${1:?usage: download-gsi.sh <url> <output> [connections]}
OUT=${2:?usage: download-gsi.sh <url> <output> [connections]}
N=${3:-12}
DIR="${OUT}.parts"

mkdir -p "$DIR"

SIZE=$(curl -sIL --max-time 40 "$URL" | tr -d '\r' \
       | awk 'tolower($1)=="content-length:"{s=$2} END{print s}')
if [ -z "${SIZE:-}" ] || [ "$SIZE" -le 0 ] 2>/dev/null; then
  echo "could not determine size (host may not support ranges); falling back to curl"
  exec curl -L --fail --retry 3 -o "$OUT" "$URL"
fi

echo "size=$SIZE bytes, connections=$N"
CHUNK=$(( (SIZE + N - 1) / N ))
CHUNK=$(( (CHUNK + 1048575) / 1048576 * 1048576 ))

for i in $(seq 0 $((N - 1))); do
  START=$(( i * CHUNK )); END=$(( START + CHUNK - 1 ))
  [ "$END" -ge "$SIZE" ] && END=$(( SIZE - 1 ))
  [ "$START" -gt "$END" ] && continue
  (
    for attempt in 1 2 3 4 5 6 7 8; do
      HAVE=0; [ -f "$DIR/part_$i" ] && HAVE=$(stat -c%s "$DIR/part_$i")
      WANT=$(( END - START + 1 ))
      [ "$HAVE" -eq "$WANT" ] && break
      if [ "$HAVE" -gt "$WANT" ]; then rm -f "$DIR/part_$i"; HAVE=0; fi
      curl -sL --fail --max-time 900 --speed-time 60 --speed-limit 1000 \
        -r $(( START + HAVE ))-"$END" "$URL" >> "$DIR/part_$i" || sleep 2
    done
  ) &
done
wait

for i in $(seq 0 $((N - 1))); do
  [ -f "$DIR/part_$i" ] && cat "$DIR/part_$i"
done > "$OUT"

GOT=$(stat -c%s "$OUT")
echo "got=$GOT expected=$SIZE"
if [ "$GOT" -ne "$SIZE" ]; then
  echo "SIZE MISMATCH — rerun (parts are kept for resume)" >&2
  exit 2
fi
rm -rf "$DIR"
echo "download complete: $OUT"
