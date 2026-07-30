#!/bin/bash
# E0: capture ROUTE_DUMP per independent slice (lockstep T tokens each).
# Usage: ./e0_capture.sh <B> <T> <max_layers> <base_offset> [threads]
set -euo pipefail
cd "$(dirname "$0")"

B=${1:?batch size}
T=${2:?tokens per slice (multiple of 128)}
MAXL=${3:?max layers}
BASE=${4:?base stream offset}
THREADS=${5:-10}
SPACING=$T

echo "E0 capture: B=$B T=$T max_layers=$MAXL base_offset=$BASE spacing=$SPACING"
for ((i=0; i<B; i++)); do
  OFF=$((BASE + i * SPACING))
  OUT="route_e0_B${B}_off${OFF}.bin"
  if [[ -f "$OUT" && $(stat -c%s "$OUT") -gt 1000 ]]; then
    echo "[skip] $OUT exists"
    continue
  fi
  echo "[$(date +%H:%M:%S)] slice $i/$B offset=$OFF -> $OUT"
  ROUTE_DUMP="$OUT" nice -n 10 ./ppl_stack_route "$T" "$MAXL" "$OFF" 0 0 "$THREADS" \
    >> "e0_capture_B${B}.log" 2>&1
done
echo "E0 capture done. Run: python3 e0_batch_union.py --glob 'route_e0_B${B}_*.bin'"