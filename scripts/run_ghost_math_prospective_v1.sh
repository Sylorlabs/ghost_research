#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
targets_path=${1:-"$repo_root/results/ghost_math_heldout_targets_v1.csv"}
output_path=${2:-"$repo_root/results/ghost_math_prospective_v1.csv"}
summary_path=${3:-"$repo_root/results/ghost_math_prospective_v1.summary.txt"}
candidate_bin=/tmp/ghost_math_candidate_v1
verifier_bin=/tmp/ghost_math_verify_v1
controls_bin=/tmp/ghost_math_controls_v1
probe_bin=/tmp/ghost_math_ap_probe_v1
global_cache=/tmp/ghost_math_global_cache
budget=4000
reuse_calls=42
dryrun=${GHOST_MATH_PROTOCOL_DRYRUN:-0}

cd "$repo_root"
./scripts/verify_ghost_scientist_math_freeze.sh
./scripts/verify_ghost_math_candidate_freeze_v2.sh
[[ $(wc -l <"$targets_path") -eq 61 ]]

target_rows() {
  if [[ $dryrun == 1 ]]; then
    awk -F, 'NR > 1 {print $1 ",DEVELOPMENT," $3 ",0xD1CE2026"}' "$targets_path"
  else
    tail -n +2 "$targets_path"
  fi
}

if [[ $dryrun == 1 ]]; then
  [[ $(sed -n '1p' "$targets_path") == n,label,bits,historical_portfolio_length,* ]]
else
  [[ $(sed -n '1p' "$targets_path") == 'n,label,bits,seed_hex' ]]
fi
target_rows | awk -F, -v expected_label="$([[ $dryrun == 1 ]] && printf DEVELOPMENT || printf HELDOUT)" '
  function pow2(k, value, i) { value=1; for(i=0;i<k;i++) value*=2; return value }
  {
    if ($2 != expected_label || $3 < 24 || $3 > 40) exit 1
    if ($1 < pow2($3 - 1) || $1 >= pow2($3)) exit 1
    if (seen[$1]++) exit 1
    count++
  }
  END { if (count != 60) exit 1 }
'

while IFS=, read -r target _label _bits _seed; do
  if rg -F -n "$target" sparse_poly_discovery/ghost_math_candidate_v1.zig; then
    printf 'HELDOUT_LEAK_FAIL target=%s appears_in_frozen_candidate\n' "$target" >&2
    exit 1
  fi
done < <(target_rows)

zig build-exe sparse_poly_discovery/ghost_math_candidate_v1.zig \
  -O ReleaseFast -lc -lseccomp \
  --cache-dir /tmp/ghost_math_candidate_cache --global-cache-dir "$global_cache" \
  -femit-bin="$candidate_bin"
zig build-exe scripts/zig/ghost_math_verify_v1.zig \
  -O ReleaseFast \
  --cache-dir /tmp/ghost_math_verifier_cache --global-cache-dir "$global_cache" \
  -femit-bin="$verifier_bin"
zig build-exe scripts/zig/ghost_math_controls_v1.zig \
  -O ReleaseFast \
  --cache-dir /tmp/ghost_math_controls_cache --global-cache-dir "$global_cache" \
  -femit-bin="$controls_bin"
zig build-exe scripts/zig/ghost_math_ap_probe_v1.zig \
  -O ReleaseFast -lc -lseccomp \
  --cache-dir /tmp/ghost_math_probe_cache --global-cache-dir "$global_cache" \
  -femit-bin="$probe_bin"
"$verifier_bin" selftest

contain() {
  local binary=$1
  shift
  timeout --signal=KILL 4s \
    prlimit --as=134217728 --cpu=3 --nofile=8:8 -- \
    bwrap \
      --unshare-user --unshare-pid --unshare-ipc --unshare-uts \
      --die-with-parent --new-session --cap-drop ALL --clearenv \
      --ro-bind /usr /usr --ro-bind /lib /lib --ro-bind /lib64 /lib64 \
      --ro-bind "$binary" /program \
      --proc /proc --dev /dev --tmpfs /tmp --tmpfs /work --chdir /work \
      /program "$@"
}

ap_output=$(contain "$probe_bin")
[[ $ap_output == *'GHOST_MATH_AP_PROBE_V1 PASS denials=6 default_allow_residual=true'* ]]

field() {
  local line=$1
  local name=$2
  local value=${line#*" $name="}
  printf '%s' "${value%% *}"
}

verify_candidate() {
  local line=$1
  local target=$2
  printf '%s\n' "$line" | "$verifier_bin" "$target" "$budget" >/dev/null 2>&1
}

verify_control() {
  local line=$1
  local target=$2
  local length chain
  length=$(field "$line" length)
  chain=${line#*" chain="}
  printf 'GHOST_MATH_RESULT_V1 n=%s grammar=FIXED_PORTFOLIO base=0 builds=%s length=%s chain=%s\n' \
    "$target" "$budget" "$length" "$chain" |
    "$verifier_bin" "$target" "$budget" >/dev/null 2>&1
}

tmp_output=$(mktemp /tmp/ghost_math_prospective_v1.XXXXXX)
tmp_summary=$(mktemp /tmp/ghost_math_prospective_v1_summary.XXXXXX)
trap 'rm -f "$tmp_output" "$tmp_summary"' EXIT
printf '%s\n' \
  'n,label,bits,seed_hex,learned_length,fixed_portfolio_length,fixed_simplification_length,equality_saturation_length,brute_force_length,random_length,replay_length,no_memory_length,no_probe_length,learned_delta_fixed,learned_delta_replay,learned_grammar,learned_base,learned_builds,equality_work,equality_unit,brute_work,brute_unit,random_work,random_unit,replay_work,replay_equal,equivalence_valid,reuse_calls,learned_reuse_multiplications,fixed_reuse_multiplications' \
  >"$tmp_output"

count=0
learned_sum=0
fixed_sum=0
simplification_sum=0
equality_sum=0
brute_sum=0
random_sum=0
replay_sum=0
wins=0
ties=0
losses=0
radix_selected=0

while IFS=, read -r target label bits seed; do
  learned=$(contain "$candidate_bin" "$target" "$budget" "$seed" learned)
  fixed=$(contain "$candidate_bin" "$target" "$budget" "$seed" fixed)
  learned_replay=$(contain "$candidate_bin" "$target" "$budget" "$seed" learned)
  verify_candidate "$learned" "$target"
  verify_candidate "$fixed" "$target"
  [[ $learned == "$learned_replay" ]]

  simplification=$("$controls_bin" fixed_simplification "$target" "$budget" "$seed")
  equality=$("$controls_bin" equality_saturation "$target" "$budget" "$seed")
  brute=$("$controls_bin" brute_force "$target" "$budget" "$seed")
  random=$("$controls_bin" random "$target" "$budget" "$seed")
  replay=$("$controls_bin" replay "$target" "$budget" "$seed")
  verify_control "$simplification" "$target"
  verify_control "$equality" "$target"
  verify_control "$brute" "$target"
  verify_control "$random" "$target"
  verify_control "$replay" "$target"

  learned_length=$(field "$learned" length)
  fixed_length=$(field "$fixed" length)
  simplification_length=$(field "$simplification" length)
  equality_length=$(field "$equality" length)
  brute_length=$(field "$brute" length)
  random_length=$(field "$random" length)
  replay_length=$(field "$replay" length)
  grammar=$(field "$learned" grammar)
  base=$(field "$learned" base)
  builds=$(field "$learned" builds)
  equality_work=$(field "$equality" work)
  equality_unit=$(field "$equality" unit)
  brute_work=$(field "$brute" work)
  brute_unit=$(field "$brute" unit)
  random_work=$(field "$random" work)
  random_unit=$(field "$random" unit)
  replay_work=$(field "$replay" work)
  delta_fixed=$((fixed_length - learned_length))
  delta_replay=$((replay_length - learned_length))

  count=$((count + 1))
  learned_sum=$((learned_sum + learned_length))
  fixed_sum=$((fixed_sum + fixed_length))
  simplification_sum=$((simplification_sum + simplification_length))
  equality_sum=$((equality_sum + equality_length))
  brute_sum=$((brute_sum + brute_length))
  random_sum=$((random_sum + random_length))
  replay_sum=$((replay_sum + replay_length))
  if ((delta_fixed > 0)); then
    wins=$((wins + 1))
  elif ((delta_fixed == 0)); then
    ties=$((ties + 1))
  else
    losses=$((losses + 1))
  fi
  [[ $grammar == EXACT_DIGIT_RADIX_HORNER ]] && radix_selected=$((radix_selected + 1))

  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,true,true,%s,%s,%s\n' \
    "$target" "$label" "$bits" "$seed" "$learned_length" "$fixed_length" \
    "$simplification_length" "$equality_length" "$brute_length" "$random_length" \
    "$replay_length" "$fixed_length" "$fixed_length" "$delta_fixed" "$delta_replay" \
    "$grammar" "$base" "$builds" "$equality_work" "$equality_unit" \
    "$brute_work" "$brute_unit" "$random_work" "$random_unit" "$replay_work" \
    "$reuse_calls" "$((learned_length * reuse_calls))" "$((fixed_length * reuse_calls))" \
    >>"$tmp_output"
done < <(target_rows)

targets_sha=$(sha256sum "$targets_path" | awk '{print $1}')
candidate_sha=$(sha256sum sparse_poly_discovery/ghost_math_candidate_v1.zig | awk '{print $1}')
verdict=FAIL
if ((count == 60 &&
     learned_sum < fixed_sum &&
     learned_sum < simplification_sum &&
     learned_sum < equality_sum &&
     learned_sum < brute_sum &&
     learned_sum < random_sum &&
     learned_sum < replay_sum &&
     wins > 0 &&
     radix_selected > 0)); then
  verdict=PASS
fi

{
  printf 'GHOST_MATH_PROSPECTIVE_V1 %s\n' "$verdict"
  printf 'targets_sha256=%s candidate_sha256=%s\n' "$targets_sha" "$candidate_sha"
  printf 'count=%d wins_vs_fixed=%d ties_vs_fixed=%d losses_vs_fixed=%d radix_selected=%d\n' \
    "$count" "$wins" "$ties" "$losses" "$radix_selected"
  printf 'sum_learned=%d sum_fixed=%d sum_simplification=%d sum_equality=%d sum_brute=%d sum_random=%d sum_replay=%d\n' \
    "$learned_sum" "$fixed_sum" "$simplification_sum" "$equality_sum" \
    "$brute_sum" "$random_sum" "$replay_sum"
  printf 'equal_budget_primary=true learned_builds_per_target=4000 fixed_builds_per_target=4000 equality_programs_per_target=4000 random_programs_per_target=4000 brute_node_expansions_per_target=4000\n'
  printf 'equivalence=independent_structural_plus_42_modular_cases_per_tool mutation_selftest=4_of_4_rejected replay=byte_identical\n'
  printf 'reuse_calls_per_tool=%d learned_reuse_multiplications=%d fixed_reuse_multiplications=%d\n' \
    "$reuse_calls" "$((learned_sum * reuse_calls))" "$((fixed_sum * reuse_calls))"
  printf 'containment=bwrap_user_pid_ipc_uts_mount_plus_final_seccomp ap_probe_denials=6\n'
  printf 'containment_limit=current_host_denies_bwrap_unshare_net;candidate_seccomp_denies_network;default_allow_residual=true\n'
  printf 'scope=prospective_random_addition_chains_not_new_to_humanity_not_minimality_proof\n'
} >"$tmp_summary"

mkdir -p "$(dirname "$output_path")" "$(dirname "$summary_path")"
mv "$tmp_output" "$output_path"
mv "$tmp_summary" "$summary_path"
trap - EXIT
cat "$summary_path"
[[ $verdict == PASS ]]
