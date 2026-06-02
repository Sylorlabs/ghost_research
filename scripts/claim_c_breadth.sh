#!/usr/bin/env bash
# Claim-C breadth stress-test (Item 3).
#
# Claim C (wcore arc): execution-only search over a FIXED primitive set produces
# novel COMPOSITIONS, never a new ATOM. The irreducibility instrument
# (wcore-invent `irreducible`) certifies, per seed, how many of the deep solvers
# the fingerprint certifier calls "novel" are actually IRREDUCIBLE to a
# known-atom composition. Claim C predicts ~0. This sweeps many seeds and
# aggregates, turning a single-seed observation into a breadth result.
#
# Run from the repo root:  bash scripts/claim_c_breadth.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/wcore/zig-out/bin/wcore-invent"

if [ ! -x "$BIN" ]; then
  echo "building wcore (ReleaseFast)..." >&2
  (cd "$ROOT/wcore" && zig build -Doptimize=ReleaseFast) >&2
fi

OUT="$ROOT/results/claim_c_breadth.csv"
SEEDS="1 2 7 42 99 1000 0x1111 0xBEEF 0xC0FFEE 0xD00D 0xACE 0x5EED 0xFACE 0x1234 0xABCD 0x9999"
tot_novel=0; tot_irr=0; tot_kill=0; nseeds=0
echo "seed,novel,irreducible,killtest_ok" | tee "$OUT"
for s in $SEEDS; do
  out="$("$BIN" irreducible "$s" 2>/dev/null)"
  novel="$(echo "$out" | grep -oE "called [0-9]+ 'novel'" | grep -oE '[0-9]+' | head -1)"
  irr="$(echo "$out" | grep -oE '[0-9]+ actually IRREDUCIBLE' | grep -oE '[0-9]+' | head -1)"
  kill="$(echo "$out" | grep -c 'distinct-count is IRREDUCIBLE' || true)"
  novel="${novel:-NA}"; irr="${irr:-NA}"
  echo "$s,$novel,$irr,$kill" | tee -a "$OUT"
  [ "$novel" != "NA" ] && tot_novel=$((tot_novel+novel)) || true
  [ "$irr" != "NA" ] && tot_irr=$((tot_irr+irr)) || true
  tot_kill=$((tot_kill+kill)); nseeds=$((nseeds+1))
done
echo "TOTALS,seeds=$nseeds,novel=$tot_novel,irreducible=$tot_irr,killtest_ok=$tot_kill" | tee -a "$OUT"
