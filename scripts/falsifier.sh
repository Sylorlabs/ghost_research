#!/usr/bin/env bash
set -uo pipefail

# MUL-Necessity Falsifier — parallel-search variant.
#
# Phase A: 8 SA searches (mul_free_challenge) in parallel; wait all.
# Phase B: 8 MMMP-L24 searches in parallel; wait all. Then serial export step.
# Phase C: Oracle gate per champion, sequential (short-circuit), in cheap-to-expensive order:
#   1. mulfree_per_bit_avalanche  (SAC matrix min >= 0.45)
#   2. verify_cli --bits=8         (Z3 bijection at W=8)
#   3. verify_cli --bits=64        (Z3 bijection at W=64, 60s timeout)
#   4. RNG_test stdin64            (PractRand 256 MiB)

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

BIN=./zig-out/bin
RNG_TEST=/home/micah/.local/bin/RNG_test

OUT=results/falsifier
mkdir -p "$OUT/sa" "$OUT/champions" "$OUT/oracles" "$OUT/logs"

VERDICTS=$OUT/verdicts.csv
echo "seed,arch,fitness,sac_min,sac_max,sac_mean,bij_w8,bij_w64,bij_w64_elapsed_ms,practrand_verdict,practrand_first_fail,gates_passed" > "$VERDICTS"

SEEDS=(
  "0x1111222233334444"
  "0xF00DCAFE12345678"
  "0xDEADBEEFBADF00D0"
  "0xACEF00DBEEFCAFE0"
  "0x0123456789ABCDEF"
  "0xCAFEBABEC0DE0001"
  "0xABCDEF0123456789"
  "0xBEEFDEADC0FFEE00"
)

SA_STEPS=100000
SA_HILL=200
MMM_ITERS=64
MMM_TIER0_INNER=120

# ───── search workers ────────────────────────────────────────────────

run_sa_worker() {
  local seed="$1"
  local label="${seed#0x}"
  "$BIN/mul_free_challenge" \
    --mode=mul_free \
    --max-prog-len=24 \
    --sa-steps=$SA_STEPS \
    --hill-iters=$SA_HILL \
    --seed=$seed \
    --output-dir=$OUT/sa \
    --label="${label}" \
    --emit-champion=1 \
    > "$OUT/logs/sa_${label}.log" 2>&1
}

run_mmm_worker() {
  local seed="$1"
  local label="${seed#0x}"
  "$BIN/mmm_holdout_hillclimb_mulfree_l24" \
    --seed=$label \
    --iters=$MMM_ITERS \
    --tier0-inner-steps=$MMM_TIER0_INNER \
    --out-subdir="falsifier/mmm_${label}" \
    --live-macro-graduation \
    > "$OUT/logs/mmm_${label}.log" 2>&1
  local rc=$?
  [[ $rc -ne 0 ]] && echo "[mmm_${label}] FAILED rc=$rc" >&2
  return $rc
}

run_mmm_export() {
  local seed="$1"
  local label="${seed#0x}"
  local meta_csv="results/falsifier/mmm_${label}/BEST_champion_meta.csv"
  local mixer_csv="$OUT/champions/mmm_${label}.csv"
  if [[ -f "$meta_csv" ]]; then
    "$BIN/meta_mixer_export_mulfree_l24" \
      --meta="$meta_csv" \
      --out="$mixer_csv" \
      --seed=$label \
      --steps=120 \
      > "$OUT/logs/mmm_export_${label}.log" 2>&1
  fi
}

# ───── oracle helpers ────────────────────────────────────────────────

verify_stdout_to_token() {
  local f="$1"
  if grep -q "verdict: VERIFIED" "$f" 2>/dev/null; then echo "VERIFIED"
  elif grep -q "verdict: COUNTER-EXAMPLE" "$f" 2>/dev/null; then echo "COUNTEREXAMPLE"
  elif grep -q "verdict: UNKNOWN" "$f" 2>/dev/null; then echo "UNKNOWN"
  elif grep -q "verdict: ERROR" "$f" 2>/dev/null; then echo "ERROR"
  else echo "PARSE_FAIL"
  fi
}

verify_elapsed_ms() {
  local v
  v=$(grep -oE "elapsed: [0-9]+ ms" "$1" 2>/dev/null | head -1 | awk '{print $2}')
  echo "${v:-NA}"
}

practrand_verdict_from() {
  if grep -q "FAIL" "$1" 2>/dev/null; then echo "FAIL"
  elif grep -q "anomalies" "$1" 2>/dev/null; then echo "PASS"
  else echo "PARSE_FAIL"
  fi
}

practrand_first_fail_from() {
  local line
  line=$(grep "FAIL" "$1" 2>/dev/null | head -1 | awk '{print $1}')
  echo "${line:-NONE}"
}

extract_sac() {
  grep -oE "$2=[0-9.]+" "$1" 2>/dev/null | head -1 | awk -F= '{print $2}'
}

extract_sa_composite() {
  grep -oE "composite=[0-9.+-eE]+" "$1" 2>/dev/null | tail -1 | awk -F= '{print $2}'
}

extract_mmm_best_holdout() {
  grep -oE "BEST_HOLDOUT = [0-9.+-eE]+" "$1" 2>/dev/null | tail -1 | awk '{print $3}'
}

# ───── oracle gate per champion ──────────────────────────────────────

gate_champion() {
  local arch="$1"
  local seed="$2"
  local csv="$3"
  local fitness="$4"

  local tag="${arch}_${seed}"
  local log_sac="$OUT/oracles/${tag}_sac.log"
  local log_w8="$OUT/oracles/${tag}_w8.log"
  local log_w64="$OUT/oracles/${tag}_w64.log"
  local log_pr="$OUT/oracles/${tag}_practrand.log"

  "$BIN/mulfree_per_bit_avalanche" --program="$csv" --samples=10000 --min=0.45 > "$log_sac" 2>&1
  local sac_exit=$?
  local sac_min sac_max sac_mean
  sac_min=$(extract_sac "$log_sac" sac_min); sac_min=${sac_min:-NA}
  sac_max=$(extract_sac "$log_sac" sac_max); sac_max=${sac_max:-NA}
  sac_mean=$(extract_sac "$log_sac" sac_mean); sac_mean=${sac_mean:-NA}

  "$BIN/verify_cli" --domain=mixer --csv="$csv" --bits=8 --timeout-ms=10000 > "$log_w8" 2>&1 || true
  local v_w8
  v_w8=$(verify_stdout_to_token "$log_w8")

  local v_w64="SKIP"
  local v_w64_ms="NA"
  if [[ "$sac_exit" == "0" && "$v_w8" == "VERIFIED" ]]; then
    timeout 75 "$BIN/verify_cli" --domain=mixer --csv="$csv" --bits=64 --timeout-ms=60000 > "$log_w64" 2>&1 || true
    v_w64=$(verify_stdout_to_token "$log_w64")
    v_w64_ms=$(verify_elapsed_ms "$log_w64")
  fi

  local pr_verdict="SKIP"
  local pr_first="NONE"
  if [[ "$sac_exit" == "0" && "$v_w8" == "VERIFIED" && ( "$v_w64" == "VERIFIED" || "$v_w64" == "UNKNOWN" ) ]]; then
    "$BIN/practrand_emit_mulfree" --program="$csv" --mode=mul_free --bytes=256M 2>/dev/null \
      | "$RNG_TEST" stdin64 -tlmax 256MB > "$log_pr" 2>&1 || true
    pr_verdict=$(practrand_verdict_from "$log_pr")
    pr_first=$(practrand_first_fail_from "$log_pr")
  fi

  local gates_passed=0
  [[ "$sac_exit" == "0" ]] && gates_passed=$((gates_passed+1))
  [[ "$v_w8" == "VERIFIED" ]] && gates_passed=$((gates_passed+1))
  [[ "$v_w64" == "VERIFIED" ]] && gates_passed=$((gates_passed+1))
  [[ "$pr_verdict" == "PASS" ]] && gates_passed=$((gates_passed+1))

  printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%d\n" \
    "$seed" "$arch" "$fitness" "$sac_min" "$sac_max" "$sac_mean" \
    "$v_w8" "$v_w64" "$v_w64_ms" "$pr_verdict" "$pr_first" "$gates_passed" \
    >> "$VERDICTS"

  echo "[$tag] sac_min=$sac_min w8=$v_w8 w64=$v_w64 practrand=$pr_verdict first_fail=$pr_first gates=$gates_passed/4"
}

# ───── orchestration ─────────────────────────────────────────────────

START=$(date +%s)

echo "=== PHASE A: SA searches in parallel (${#SEEDS[@]} jobs, sa_steps=$SA_STEPS, hill_iters=$SA_HILL) ==="
PHASE_A_START=$(date +%s)
SA_PIDS=()
for seed in "${SEEDS[@]}"; do
  run_sa_worker "$seed" &
  SA_PIDS+=($!)
done
for pid in "${SA_PIDS[@]}"; do
  wait "$pid"
done
echo "Phase A done in $(($(date +%s) - PHASE_A_START))s"

echo ""
echo "=== PHASE B: MMMP-L24 searches in parallel (${#SEEDS[@]} jobs, iters=$MMM_ITERS) ==="
PHASE_B_START=$(date +%s)
MMM_PIDS=()
for seed in "${SEEDS[@]}"; do
  run_mmm_worker "$seed" &
  MMM_PIDS+=($!)
done
for pid in "${MMM_PIDS[@]}"; do
  wait "$pid"
done
echo "Phase B (search) done in $(($(date +%s) - PHASE_B_START))s"

echo "=== PHASE B.2: MMMP exports (serial, cheap) ==="
for seed in "${SEEDS[@]}"; do
  run_mmm_export "$seed"
done

echo ""
echo "=== PHASE C: Oracle gate per champion (sequential, short-circuit) ==="
PHASE_C_START=$(date +%s)
for seed in "${SEEDS[@]}"; do
  label="${seed#0x}"
  sa_csv="$OUT/sa/champion_${label}.csv"
  mmm_csv="$OUT/champions/mmm_${label}.csv"

  if [[ -f "$sa_csv" ]]; then
    sa_fit=$(extract_sa_composite "$OUT/logs/sa_${label}.log"); sa_fit=${sa_fit:-NA}
    gate_champion "sa" "$label" "$sa_csv" "$sa_fit"
  else
    echo "[sa_$label] MISSING champion CSV (search failed?)"
  fi

  if [[ -f "$mmm_csv" ]]; then
    mmm_fit=$(extract_mmm_best_holdout "$OUT/logs/mmm_${label}.log"); mmm_fit=${mmm_fit:-NA}
    gate_champion "mmm" "$label" "$mmm_csv" "$mmm_fit"
  else
    echo "[mmm_$label] MISSING champion CSV (export failed?)"
  fi
done
echo "Phase C done in $(($(date +%s) - PHASE_C_START))s"

END=$(date +%s)
echo ""
echo "=== FALSIFIER BATCH COMPLETE ==="
echo "total elapsed: $((END - START))s"
echo "verdicts:      $VERDICTS"
echo ""
echo "=== gate-pass histogram ==="
awk -F, 'NR>1 {h[$12]++} END {for (k in h) printf "gates_passed=%s  count=%d\n", k, h[k]}' "$VERDICTS" | sort

CRACKERS=$(awk -F, 'NR>1 && $12==4 {print}' "$VERDICTS")
if [[ -n "$CRACKERS" ]]; then
  echo ""
  echo "*** MUL-NECESSITY CONJECTURE CRACKED ***"
  echo "$CRACKERS"
else
  echo ""
  echo "MUL-necessity conjecture HARDENED: 0 of $((${#SEEDS[@]} * 2)) (seeds x arches) cleared all four oracles"
fi
