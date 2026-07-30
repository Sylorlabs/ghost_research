#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

check() {
  local expected=$1 path=$2 actual
  actual=$(sha256sum "$path" | awk '{print $1}')
  [[ $actual == "$expected" ]] || {
    printf 'V1_ATTESTATION_MISMATCH %s expected=%s actual=%s\n' "$path" "$expected" "$actual" >&2
    exit 1
  }
  printf 'V1_ATTESTATION_OK %s %s\n' "$actual" "$path"
}

check 8a17c39be10b7fad1c215dd2be5979e21d7971a98156e0f1f2bee87b0d8a3432 results/ghost_math_protocol_freeze_v3.txt
check 1d5a9b32772ecfa4b911e17a095b6bd10d1a3a10935c61928fbeb5f1859314bd scripts/verify_ghost_math_protocol_freeze_v3.sh
check eab2adec189666581bba9cb6776bbc32d3347bcf5e51c187a912cc8781577a32 results/ghost_math_heldout_targets_v1.csv
check b468c3ea7605f656557282a5a1f8c7ae5089cfa0b2d94112eb7b51fa3da01168 results/ghost_math_prospective_v1.csv
check 4f0e03acd5f47929a004c2adc72f48bab0ab00fc78809711eae83d4aeb3df161 results/ghost_math_prospective_v1.summary.txt
printf 'GHOST_MATH_PROSPECTIVE_V1_ATTESTATION PASS verdict=NEGATIVE\n'
