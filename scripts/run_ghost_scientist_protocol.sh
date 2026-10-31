#!/usr/bin/env bash
set -euo pipefail

# Fresh-build and replay the candidate constructor and the evaluator-owned
# real-artifact protocol. The candidate binary is tested separately; the
# integrated evaluator imports only its public program-construction API.

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

run_root=$(mktemp -d /tmp/ghost-scientist-protocol.XXXXXX)
cleanup() {
  case "$run_root" in
    /tmp/ghost-scientist-protocol.*) rm -rf -- "$run_root" ;;
    *) printf 'refusing unsafe cleanup target: %s\n' "$run_root" >&2 ;;
  esac
}
trap cleanup EXIT

mkdir -p \
  "$run_root/luna-cache" \
  "$run_root/luna-global" \
  "$run_root/terra-cache" \
  "$run_root/terra-global" \
  results

zig build-exe sparse_poly_discovery/ghost_scientist_constructor_luna.zig \
  -O ReleaseSafe \
  --cache-dir "$run_root/luna-cache" \
  --global-cache-dir "$run_root/luna-global" \
  -femit-bin="$run_root/constructor"

zig build-exe sparse_poly_discovery/ghost_scientist_evaluator_terra.zig \
  -O ReleaseSafe \
  --cache-dir "$run_root/terra-cache" \
  --global-cache-dir "$run_root/terra-global" \
  -femit-bin="$run_root/evaluator"

"$run_root/constructor" selftest
"$run_root/evaluator" selftest

"$run_root/constructor" run "$run_root/constructor-a.csv"
"$run_root/constructor" run "$run_root/constructor-b.csv"
cmp "$run_root/constructor-a.csv" "$run_root/constructor-b.csv"

"$run_root/evaluator" run "$run_root/evaluator-a.csv"
"$run_root/evaluator" run "$run_root/evaluator-b.csv"
cmp "$run_root/evaluator-a.csv" "$run_root/evaluator-b.csv"

install -m 0644 "$run_root/constructor-a.csv" \
  results/ghost_scientist_constructor_luna.csv
install -m 0644 "$run_root/evaluator-a.csv" \
  results/ghost_scientist_protocol.csv

printf 'constructor_sha256 '
sha256sum results/ghost_scientist_constructor_luna.csv | cut -d' ' -f1
printf 'protocol_sha256 '
sha256sum results/ghost_scientist_protocol.csv | cut -d' ' -f1
tail -n 12 results/ghost_scientist_protocol.csv
