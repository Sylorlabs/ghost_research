#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

check() {
  local expected=$1
  local path=$2
  local observed
  observed=$(sha256sum "$path" | cut -d' ' -f1)
  if [[ "$observed" != "$expected" ]]; then
    printf 'FREEZE_MISMATCH path=%s expected=%s observed=%s\n' \
      "$path" "$expected" "$observed" >&2
    return 1
  fi
  printf 'FREEZE_OK %s %s\n' "$observed" "$path"
}

check 3aa7002bab26ce5f7be0d3cac65360494d294d7399d7e70d7dfd5b1e608f86b3 \
  sparse_poly_discovery/ghost_scientist_constructor_luna.zig
check ceee5e98eb89cf607fbf115278e1a2d883f19aaa4c2fca8f4a3d81744e0a1258 \
  sparse_poly_discovery/ghost_scientist_evaluator_terra.zig
check d61db5d8acf20bb202ef153388088dae5ce2887021f0f97d87b58099d3c8e812 \
  sparse_poly_discovery/method_memory_firewall_round_aw.zig
check eb67ca4656d53653e89560fbaec806e8a708cd811f8f1c66888e0beec5041e03 \
  results/method_memory_firewall_round_aw.csv
check 2353461bc68b55b2f2b7fd8e246b5e92c14833edfcd2eed838469e807c378f7b \
  scripts/run_ghost_scientist_protocol.sh
check 71d39545dea0d789f5f2f4a520a6b69d7b333c21e19db1f8cd052fee37e6dbc0 \
  results/ghost_scientist_protocol.csv

printf 'GHOST_SCIENTIST_MATH_FREEZE_V1 PASS\n'
