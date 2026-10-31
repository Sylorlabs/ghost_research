#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"
./scripts/verify_ghost_math_prospective_v1_attestation.sh

check() {
  local expected=$1 path=$2 actual
  actual=$(sha256sum "$path" | awk '{print $1}')
  [[ $actual == "$expected" ]] || {
    printf 'V2_FREEZE_MISMATCH %s expected=%s actual=%s\n' "$path" "$expected" "$actual" >&2
    exit 1
  }
  printf 'V2_FREEZE_OK %s %s\n' "$actual" "$path"
}

check eff138657114af3f6c6cef18e3b6374bd1496bf151eeb956ac3b00c0e3c59e00 sparse_poly_discovery/ghost_math_candidate_v1.zig
check 84bd282ac574eea12290823e6b5b6293e40228a6e7b2e0c456156a40bd6a7487 sparse_poly_discovery/ghost_math_radix_v2.zig
check f158346a556a53d825a45777cf32ec60f4f158378110cc056d5cdd6ccaa64752 scripts/zig/ghost_math_verify_v1.zig
check 2c88f22e9ced4ee69c80009c3b868c84006e4b8983bbb6f9377d77916e21f4a7 scripts/zig/ghost_math_controls_v1.zig
check 5ff09f805e52f1c7da4c939ed11465e120da263a68aa39c2927eb3dcaf5b9c5d scripts/zig/ghost_math_ap_probe_v1.zig
check 2c8933d48c5ec885290421b97f126f55b9f720ea907e133a214dee9503b4f39f scripts/zig/ghost_math_generate_targets_v1.zig
check 8a17c39be10b7fad1c215dd2be5979e21d7971a98156e0f1f2bee87b0d8a3432 results/ghost_math_protocol_freeze_v3.txt
check 5e5a0b398dad5ff8493661f7928103b65062dbd270317c67b3d98289a0693ee1 results/ghost_math_prospective_v1_attestation.txt
check 095b0566b6e02cc74bc76cf338f87b660b6993a343918e8b60b5552ffe21b730 scripts/verify_ghost_math_prospective_v1_attestation.sh
check b1fed9724bb7727c8327774e9147814c2f6385f0e8b25b294922a8af1f36b669 results/ghost_math_v2_development.summary.txt

while IFS=, read -r target _; do
  [[ $target == n ]] && continue
  if rg -F -n "$target" sparse_poly_discovery/ghost_math_radix_v2.zig; then
    printf 'V2_DEVELOPMENT_TARGET_LEAK %s\n' "$target" >&2
    exit 1
  fi
done <results/ghost_math_heldout_targets_v1.csv
printf 'V2_DEVELOPMENT_TARGET_LEAK_SCAN_OK\n'
printf 'GHOST_MATH_CANDIDATE_V2_FREEZE_V4 PASS fresh_target_present=%s\n' \
  "$([[ -e results/ghost_math_heldout_targets_v2.csv ]] && printf true || printf false)"
