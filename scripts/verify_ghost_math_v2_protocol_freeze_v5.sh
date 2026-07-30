#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"
./scripts/verify_ghost_math_candidate_v2_freeze_v4.sh

check() {
  local expected=$1 path=$2 actual
  actual=$(sha256sum "$path" | awk '{print $1}')
  [[ $actual == "$expected" ]] || {
    printf 'V2_PROTOCOL_FREEZE_MISMATCH %s expected=%s actual=%s\n' "$path" "$expected" "$actual" >&2
    exit 1
  }
  printf 'V2_PROTOCOL_FREEZE_OK %s %s\n' "$actual" "$path"
}

check d3efa5eceec949f94155fd63933fc2d1568755ee2fc90bcb1625d3541c76d66a results/ghost_math_candidate_v2_freeze_v4.txt
check eb0ac1cfd6be14caa91364c1c716ce88696e234f5b39221500e22898e7426f50 scripts/verify_ghost_math_candidate_v2_freeze_v4.sh
check ecc52925634a944f2ce449f5618949fce8d8dec793319259a69aea34bf4b7028 scripts/run_ghost_math_prospective_v2.sh
check 21875b8573270999ecf78a8ed1154469dbeab3531352d463d818ce17a3d393ab results/ghost_math_v2_protocol_dryrun.summary.txt
check 2c8933d48c5ec885290421b97f126f55b9f720ea907e133a214dee9503b4f39f scripts/zig/ghost_math_generate_targets_v1.zig
check 2c88f22e9ced4ee69c80009c3b868c84006e4b8983bbb6f9377d77916e21f4a7 scripts/zig/ghost_math_controls_v1.zig
check 5ff09f805e52f1c7da4c939ed11465e120da263a68aa39c2927eb3dcaf5b9c5d scripts/zig/ghost_math_ap_probe_v1.zig
check f158346a556a53d825a45777cf32ec60f4f158378110cc056d5cdd6ccaa64752 scripts/zig/ghost_math_verify_v1.zig
bash -n scripts/run_ghost_math_prospective_v2.sh
printf 'GHOST_MATH_V2_PROTOCOL_FREEZE_V5 PASS fresh_target_present=%s\n' \
  "$([[ -e results/ghost_math_heldout_targets_v2.csv ]] && printf true || printf false)"
