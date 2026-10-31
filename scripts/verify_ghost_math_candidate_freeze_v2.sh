#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

check() {
  local expected=$1
  local path=$2
  local actual
  actual=$(sha256sum "$path" | awk '{print $1}')
  if [[ $actual != "$expected" ]]; then
    printf 'FREEZE_MISMATCH %s expected=%s actual=%s\n' "$path" "$expected" "$actual" >&2
    exit 1
  fi
  printf 'FREEZE_OK %s %s\n' "$actual" "$path"
}

check eff138657114af3f6c6cef18e3b6374bd1496bf151eeb956ac3b00c0e3c59e00 sparse_poly_discovery/ghost_math_candidate_v1.zig
check f158346a556a53d825a45777cf32ec60f4f158378110cc056d5cdd6ccaa64752 scripts/zig/ghost_math_verify_v1.zig
check 820c419bd3650246a00711a6398dbf08157cfb107cc9120422834aabe92903ee scripts/run_ghost_math_development_v1.sh
check 12874fa6ca055291eeb00f02fb38f6afa36e7270ad8a22c9ea6c2d950c98ab68 results/ghost_math_development_v1.csv
check ec0f33f8895ab6281c6b76a2962e491f1c114f48ea8ff2be576f14723dec6890 boundary_crossing/addchain_v2.zig
check 5516588fa7d4fb2e34e43af541b4eae6aff956496e367a187c6291dd5c9f603f results/addchain_v2_2026_07_10.csv
check f5d08cbe6e2272cf727e918db93884371aadeef33f93bbd4385bafaec26612cf results/ghost_scientist_math_freeze_v1.txt

if rg -n 'heldout|HOLDOUT|83068450|902013578|16512375905' \
  sparse_poly_discovery/ghost_math_candidate_v1.zig >/tmp/ghost_math_freeze_leak_scan.txt; then
  printf 'FREEZE_LEAK_SCAN_FAIL\n' >&2
  cat /tmp/ghost_math_freeze_leak_scan.txt >&2
  exit 1
fi
printf 'FREEZE_LEAK_SCAN_OK candidate_contains_no_heldout_marker_or_development_winner_constants\n'
printf 'GHOST_MATH_CANDIDATE_FREEZE_V2 PASS heldout_not_yet_generated=true\n'
