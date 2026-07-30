#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
freeze_path="$repo_root/ghost_scientist/results/ghost_ruler_protocol_freeze_v3.txt"
[[ -f $freeze_path ]]
cd "$repo_root"
sed -n '/^sha256_records_begin$/,/^sha256_records_end$/p' "$freeze_path" |
  sed '1d;$d' |
  sha256sum --check --strict
printf 'GHOST_RULER_FREEZE_V3 PASS freeze=%s\n' "$freeze_path"
