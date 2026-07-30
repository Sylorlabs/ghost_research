#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
output_path=${1:-"$repo_root/results/ghost_math_development_v1.csv"}
candidate_bin=/tmp/ghost_math_candidate_v1
verifier_bin=/tmp/ghost_math_verify_v1
candidate_cache=/tmp/ghost_math_candidate_cache
verifier_cache=/tmp/ghost_math_verifier_cache
global_cache=/tmp/ghost_math_global_cache
seed=0xD1CE2026
budget=4000

cd "$repo_root"
zig build-exe sparse_poly_discovery/ghost_math_candidate_v1.zig \
  -O ReleaseFast -lc -lseccomp \
  --cache-dir "$candidate_cache" --global-cache-dir "$global_cache" \
  -femit-bin="$candidate_bin"
zig build-exe scripts/zig/ghost_math_verify_v1.zig \
  -O ReleaseFast \
  --cache-dir "$verifier_cache" --global-cache-dir "$global_cache" \
  -femit-bin="$verifier_bin"
"$verifier_bin" selftest

launch() {
  local target=$1
  local mode=$2
  timeout --signal=KILL 4s \
    prlimit --as=134217728 --cpu=3 --nofile=8:8 -- \
    bwrap \
      --unshare-user --unshare-pid --unshare-ipc --unshare-uts \
      --die-with-parent --new-session --cap-drop ALL --clearenv \
      --ro-bind /usr /usr --ro-bind /lib /lib --ro-bind /lib64 /lib64 \
      --ro-bind "$candidate_bin" /candidate \
      --proc /proc --dev /dev --tmpfs /tmp --tmpfs /work --chdir /work \
      /candidate "$target" "$budget" "$seed" "$mode"
}

field() {
  local line=$1
  local name=$2
  local value=${line#*" $name="}
  printf '%s' "${value%% *}"
}

tmp_output=$(mktemp /tmp/ghost_math_development_v1.XXXXXX)
trap 'rm -f "$tmp_output"' EXIT
printf '%s\n' \
  'n,label,bits,historical_portfolio_length,fixed_length,learned_length,delta_vs_fixed,delta_vs_historical,grammar,base,builds,valid,replay_equal' \
  >"$tmp_output"

count=0
wins=0
ties=0
losses=0
fixed_sum=0
learned_sum=0
historical_sum=0
historical_wins=0
historical_losses=0
while IFS=, read -r target label bits historical; do
  fixed=$(launch "$target" fixed)
  learned=$(launch "$target" learned)
  replay=$(launch "$target" learned)
  printf '%s\n' "$fixed" | "$verifier_bin" "$target" "$budget"
  printf '%s\n' "$learned" | "$verifier_bin" "$target" "$budget"
  [[ $learned == "$replay" ]]

  fixed_length=$(field "$fixed" length)
  learned_length=$(field "$learned" length)
  grammar=$(field "$learned" grammar)
  base=$(field "$learned" base)
  builds=$(field "$learned" builds)
  delta_fixed=$((fixed_length - learned_length))
  delta_historical=$((historical - learned_length))

  count=$((count + 1))
  fixed_sum=$((fixed_sum + fixed_length))
  learned_sum=$((learned_sum + learned_length))
  historical_sum=$((historical_sum + historical))
  if ((delta_fixed > 0)); then
    wins=$((wins + 1))
  elif ((delta_fixed == 0)); then
    ties=$((ties + 1))
  else
    losses=$((losses + 1))
  fi
  if ((delta_historical > 0)); then
    historical_wins=$((historical_wins + 1))
  elif ((delta_historical < 0)); then
    historical_losses=$((historical_losses + 1))
  fi
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,true,true\n' \
    "$target" "$label" "$bits" "$historical" "$fixed_length" "$learned_length" \
    "$delta_fixed" "$delta_historical" "$grammar" "$base" "$builds" \
    >>"$tmp_output"
done < <(awk -F, 'NR > 1 && $2 == "MID" {print $1 "," $2 "," $3 "," $13}' \
  results/addchain_v2_2026_07_10.csv)

if ((count != 60 || wins == 0 || losses != 0 || learned_sum >= fixed_sum ||
     learned_sum >= historical_sum)); then
  printf 'DEVELOPMENT_GATE_FAIL count=%d wins=%d ties=%d losses=%d fixed_sum=%d learned_sum=%d historical_sum=%d\n' \
    "$count" "$wins" "$ties" "$losses" "$fixed_sum" "$learned_sum" "$historical_sum" >&2
  exit 1
fi

mkdir -p "$(dirname "$output_path")"
mv "$tmp_output" "$output_path"
trap - EXIT
printf 'GHOST_MATH_DEVELOPMENT_V1 PASS count=%d matched_wins=%d ties=%d losses=%d fixed_sum=%d learned_sum=%d historical_sum=%d historical_wins=%d historical_losses=%d replay=byte_identical\n' \
  "$count" "$wins" "$ties" "$losses" "$fixed_sum" "$learned_sum" \
  "$historical_sum" "$historical_wins" "$historical_losses"
printf 'AP_COMPATIBILITY_NOTE namespace_mount_pid_ipc_uts_user=true network_namespace=false candidate_seccomp_network_denial=true host_bwrap_unshare_net_denied=true\n'
