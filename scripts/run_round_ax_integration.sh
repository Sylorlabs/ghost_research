#!/usr/bin/env bash
set -euo pipefail

# AX4 coordinator: stage AW's real tracked artifacts, run all 27 equal-budget
# grid identities, then independently reduce their typed witnesses.  The shell
# is coordinator-only and is intentionally not candidate-visible.
root="/tmp/round-ax-sealed"
claims="/tmp/round-ax-typed-claims.txt"
mkdir -p results
zig run sparse_poly_discovery/sealed_multitask_corpus_round_aw.zig -- stage "$root"
: > "$claims"
for worker in $(seq 0 26); do
  case $((worker / 9)) in
    0) grammar=source ;;
    1) grammar=csv ;;
    2) grammar=control_flow ;;
  esac
  zig run sparse_poly_discovery/ax_real_integration_round_ax.zig -- emit "$root" "$worker" "$grammar" "/tmp/round-ax-worker-${worker}.txt"
  cat "/tmp/round-ax-worker-${worker}.txt" >> "$claims"
done
zig run sparse_poly_discovery/ax_real_integration_round_ax.zig -- evaluate "$root" "$claims" results/ax_real_integration_round_ax.csv
tail -1 results/ax_real_integration_round_ax.csv
