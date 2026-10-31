#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"
./scripts/verify_ghost_math_candidate_freeze_v2.sh

check() {
  local expected=$1
  local path=$2
  local actual
  actual=$(sha256sum "$path" | awk '{print $1}')
  if [[ $actual != "$expected" ]]; then
    printf 'PROTOCOL_FREEZE_MISMATCH %s expected=%s actual=%s\n' "$path" "$expected" "$actual" >&2
    exit 1
  fi
  printf 'PROTOCOL_FREEZE_OK %s %s\n' "$actual" "$path"
}

check 3e6b8e3fc5c9579b5def40483cc4f839dee3eefd49e02acc50fd5ae1419c0cd0 results/ghost_math_candidate_freeze_v2.txt
check a0164d9cef617b085305682037123eec32e52c73275775297be5f7a714edfdec scripts/verify_ghost_math_candidate_freeze_v2.sh
check 2c88f22e9ced4ee69c80009c3b868c84006e4b8983bbb6f9377d77916e21f4a7 scripts/zig/ghost_math_controls_v1.zig
check 2c8933d48c5ec885290421b97f126f55b9f720ea907e133a214dee9503b4f39f scripts/zig/ghost_math_generate_targets_v1.zig
check 5ff09f805e52f1c7da4c939ed11465e120da263a68aa39c2927eb3dcaf5b9c5d scripts/zig/ghost_math_ap_probe_v1.zig
check db4812caa471377b5daed83aa76a3eb421472397992681ca6d1273aee74a7f4d scripts/run_ghost_math_prospective_v1.sh
check 1c4e55e1340b0007c12a07d8755552592fb77985cf52859ad304dd871fde4e22 results/ghost_math_protocol_dryrun_v1.summary.txt

bash -n scripts/run_ghost_math_prospective_v1.sh
zig fmt --check scripts/zig/ghost_math_controls_v1.zig \
  scripts/zig/ghost_math_generate_targets_v1.zig \
  scripts/zig/ghost_math_ap_probe_v1.zig
printf 'GHOST_MATH_PROTOCOL_FREEZE_V3 PASS target_file_present=%s\n' \
  "$([[ -e results/ghost_math_heldout_targets_v1.csv ]] && printf true || printf false)"
