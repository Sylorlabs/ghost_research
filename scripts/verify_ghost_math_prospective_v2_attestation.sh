#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

check() {
  local expected=$1 path=$2 actual
  actual=$(sha256sum "$path" | awk '{print $1}')
  [[ $actual == "$expected" ]] || {
    printf 'V2_OUTCOME_MISMATCH %s expected=%s actual=%s\n' "$path" "$expected" "$actual" >&2
    exit 1
  }
  printf 'V2_OUTCOME_OK %s %s\n' "$actual" "$path"
}

check 17dddc67811052a168f9d571b4d00d516f6da7bd8310bcced713af7b21211a25 results/ghost_math_v2_protocol_freeze_v5.txt
check 469d08a71d69b04c367faeab0f8010cad519d1d123624d6d42290602f6bcea0f scripts/verify_ghost_math_v2_protocol_freeze_v5.sh
check 61aa1b8b375b0460ce6358c6a03748af7d4cccbb0a95aeb6fe84bff19bd3cc93 results/ghost_math_heldout_targets_v2.csv
check 8e91b299095b204281f6fda2b23911f8c715b0c788edf7d8055093f822307bf5 results/ghost_math_prospective_v2.csv
check 059cdd93828c24cc316ade7612eb886c922fcc37c5607b8eeca4629d71e8eff6 results/ghost_math_prospective_v2.summary.txt
check eff138657114af3f6c6cef18e3b6374bd1496bf151eeb956ac3b00c0e3c59e00 sparse_poly_discovery/ghost_math_candidate_v1.zig
check 84bd282ac574eea12290823e6b5b6293e40228a6e7b2e0c456156a40bd6a7487 sparse_poly_discovery/ghost_math_radix_v2.zig

awk -F, '
  NR == 1 {
    if (NF != 34) exit 1
    next
  }
  {
    if (NF != 34 || $20 != 48000 || $21 != 96000 ||
        $29 != "true" || $30 != "true" || $31 != "true") exit 1
    count++; hybrid += $5; fixed += $6
    simpl += $8; equality += $9; brute += $10; random += $11; replay += $12
    if ($15 > 0) wins++; else if ($15 == 0) ties++; else losses++
    if ($19 > 0) selected++
  }
  END {
    if (count != 60 || wins != 9 || ties != 51 || losses != 0 || selected != 9 ||
        hybrid != 2364 || fixed != 2373 || simpl != 2787 || equality != 2542 ||
        brute != 2787 || random != 2787 || replay != 2523) exit 1
  }
' results/ghost_math_prospective_v2.csv
printf 'GHOST_MATH_PROSPECTIVE_V2_ATTESTATION PASS verdict=POSITIVE\n'
