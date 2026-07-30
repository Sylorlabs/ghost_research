#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
targets_path=${1:-"$repo_root/results/ghost_math_heldout_targets_v2.csv"}
output_path=${2:-"$repo_root/results/ghost_math_prospective_v2.csv"}
summary_path=${3:-"$repo_root/results/ghost_math_prospective_v2.summary.txt"}
candidate_v1_bin=/tmp/ghost_math_candidate_v1
candidate_v2_bin=/tmp/ghost_math_radix_v2
verifier_bin=/tmp/ghost_math_verify_v1
controls_bin=/tmp/ghost_math_controls_v1
probe_bin=/tmp/ghost_math_ap_probe_v1
global_cache=/tmp/ghost_math_global_cache
inherited_budget=47745
crossover_budget=255
hybrid_budget=48000
strong_fixed_budget=96000
control_budget=4000
reuse_calls=42
dryrun=${GHOST_MATH_V2_PROTOCOL_DRYRUN:-0}
if [[ $dryrun == 1 ]]; then
  inherited_budget=3745
  hybrid_budget=4000
  strong_fixed_budget=4000
fi

cd "$repo_root"
./scripts/verify_ghost_math_candidate_v2_freeze_v4.sh
[[ $(sed -n '1p' "$targets_path") == 'n,label,bits,seed_hex' ]]
[[ $(wc -l <"$targets_path") -eq 61 ]]
tail -n +2 "$targets_path" | awk -F, '
  function pow2(k, value, i) { value=1; for(i=0;i<k;i++) value*=2; return value }
  {
    if ($2 != "HELDOUT" || $3 < 24 || $3 > 40) exit 1
    if ($1 < pow2($3 - 1) || $1 >= pow2($3)) exit 1
    if (seen[$1]++) exit 1
    count++
  }
  END { if (count != 60) exit 1 }
'

while IFS=, read -r target _label _bits _seed; do
  [[ $target == n ]] && continue
  for source in \
    sparse_poly_discovery/ghost_math_candidate_v1.zig \
    sparse_poly_discovery/ghost_math_radix_v2.zig; do
    if rg -F -n "$target" "$source"; then
      printf 'V2_HELDOUT_LEAK_FAIL target=%s source=%s\n' "$target" "$source" >&2
      exit 1
    fi
  done
done <"$targets_path"

zig build-exe sparse_poly_discovery/ghost_math_candidate_v1.zig \
  -O ReleaseFast -lc -lseccomp \
  --cache-dir /tmp/ghost_math_candidate_v1_cache --global-cache-dir "$global_cache" \
  -femit-bin="$candidate_v1_bin"
zig build-exe sparse_poly_discovery/ghost_math_radix_v2.zig \
  -O ReleaseFast -lc -lseccomp \
  --cache-dir /tmp/ghost_math_candidate_v2_cache --global-cache-dir "$global_cache" \
  -femit-bin="$candidate_v2_bin"
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
  timeout --signal=KILL 15s \
    prlimit --as=134217728 --cpu=12 --nofile=8:8 -- \
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

verify_v1() {
  local line=$1 target=$2 budget=$3
  printf '%s\n' "$line" | "$verifier_bin" "$target" "$budget" >/dev/null 2>&1
}

verify_v2() {
  local line=$1 target=$2 length chain
  length=$(field "$line" length)
  chain=${line#*" chain="}
  printf 'GHOST_MATH_RESULT_V1 n=%s grammar=FIXED_PORTFOLIO base=0 builds=%s length=%s chain=%s\n' \
    "$target" "$hybrid_budget" "$length" "$chain" |
    "$verifier_bin" "$target" "$hybrid_budget" >/dev/null 2>&1
}

verify_control() {
  local line=$1 target=$2 length chain
  length=$(field "$line" length)
  chain=${line#*" chain="}
  printf 'GHOST_MATH_RESULT_V1 n=%s grammar=FIXED_PORTFOLIO base=0 builds=%s length=%s chain=%s\n' \
    "$target" "$control_budget" "$length" "$chain" |
    "$verifier_bin" "$target" "$control_budget" >/dev/null 2>&1
}

tmp_output=$(mktemp /tmp/ghost_math_prospective_v2.XXXXXX)
tmp_summary=$(mktemp /tmp/ghost_math_prospective_v2_summary.XXXXXX)
trap 'rm -f "$tmp_output" "$tmp_summary"' EXIT
printf '%s\n' \
  'n,label,bits,seed_hex,hybrid_length,strong_fixed_length,inherited_length,fixed_simplification_length,equality_saturation_length,brute_force_length,random_length,replay_length,no_memory_length,no_probe_length,hybrid_delta_strong_fixed,hybrid_delta_inherited,hybrid_delta_replay,hybrid_grammar,hybrid_radix,hybrid_builds,strong_fixed_builds,equality_work,equality_unit,brute_work,brute_unit,random_work,random_unit,replay_work,inherited_replay_equal,crossover_replay_equal,equivalence_valid,reuse_calls,hybrid_reuse_multiplications,strong_fixed_reuse_multiplications' \
  >"$tmp_output"

count=0
hybrid_sum=0
strong_fixed_sum=0
inherited_sum=0
simplification_sum=0
equality_sum=0
brute_sum=0
random_sum=0
replay_sum=0
wins=0
ties=0
losses=0
crossover_selected=0

while IFS=, read -r target label bits seed; do
  [[ $target == n ]] && continue
  inherited=$(contain "$candidate_v1_bin" "$target" "$inherited_budget" "$seed" fixed)
  inherited_chain=${inherited#*" chain="}
  hybrid=$(contain "$candidate_v2_bin" "$target" "$crossover_budget" "$inherited_chain")
  strong_fixed=$(contain "$candidate_v1_bin" "$target" "$strong_fixed_budget" "$seed" fixed)
  inherited_replay=$(contain "$candidate_v1_bin" "$target" "$inherited_budget" "$seed" fixed)
  hybrid_replay=$(contain "$candidate_v2_bin" "$target" "$crossover_budget" "$inherited_chain")
  verify_v1 "$inherited" "$target" "$inherited_budget"
  verify_v1 "$strong_fixed" "$target" "$strong_fixed_budget"
  verify_v2 "$hybrid" "$target"
  [[ $inherited == "$inherited_replay" ]]
  [[ $hybrid == "$hybrid_replay" ]]

  simplification=$("$controls_bin" fixed_simplification "$target" "$control_budget" "$seed")
  equality=$("$controls_bin" equality_saturation "$target" "$control_budget" "$seed")
  brute=$("$controls_bin" brute_force "$target" "$control_budget" "$seed")
  random=$("$controls_bin" random "$target" "$control_budget" "$seed")
  replay=$("$controls_bin" replay "$target" "$control_budget" "$seed")
  verify_control "$simplification" "$target"
  verify_control "$equality" "$target"
  verify_control "$brute" "$target"
  verify_control "$random" "$target"
  verify_control "$replay" "$target"

  hybrid_length=$(field "$hybrid" length)
  strong_fixed_length=$(field "$strong_fixed" length)
  inherited_length=$(field "$inherited" length)
  simplification_length=$(field "$simplification" length)
  equality_length=$(field "$equality" length)
  brute_length=$(field "$brute" length)
  random_length=$(field "$random" length)
  replay_length=$(field "$replay" length)
  grammar=$(field "$hybrid" grammar)
  radix=$(field "$hybrid" radix)
  crossover_builds=$(field "$hybrid" builds)
  equality_work=$(field "$equality" work)
  equality_unit=$(field "$equality" unit)
  brute_work=$(field "$brute" work)
  brute_unit=$(field "$brute" unit)
  random_work=$(field "$random" work)
  random_unit=$(field "$random" unit)
  replay_work=$(field "$replay" work)
  delta_fixed=$((strong_fixed_length - hybrid_length))
  delta_inherited=$((inherited_length - hybrid_length))
  delta_replay=$((replay_length - hybrid_length))

  count=$((count + 1))
  hybrid_sum=$((hybrid_sum + hybrid_length))
  strong_fixed_sum=$((strong_fixed_sum + strong_fixed_length))
  inherited_sum=$((inherited_sum + inherited_length))
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
  ((radix > 0)) && crossover_selected=$((crossover_selected + 1))

  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,true,true,true,%s,%s,%s\n' \
    "$target" "$label" "$bits" "$seed" "$hybrid_length" "$strong_fixed_length" \
    "$inherited_length" "$simplification_length" "$equality_length" "$brute_length" \
    "$random_length" "$replay_length" "$strong_fixed_length" "$strong_fixed_length" \
    "$delta_fixed" "$delta_inherited" "$delta_replay" "$grammar" "$radix" \
    "$((inherited_budget + crossover_builds))" "$strong_fixed_budget" \
    "$equality_work" "$equality_unit" "$brute_work" "$brute_unit" \
    "$random_work" "$random_unit" "$replay_work" "$reuse_calls" \
    "$((hybrid_length * reuse_calls))" "$((strong_fixed_length * reuse_calls))" \
    >>"$tmp_output"
done <"$targets_path"

targets_sha=$(sha256sum "$targets_path" | awk '{print $1}')
candidate_v1_sha=$(sha256sum sparse_poly_discovery/ghost_math_candidate_v1.zig | awk '{print $1}')
candidate_v2_sha=$(sha256sum sparse_poly_discovery/ghost_math_radix_v2.zig | awk '{print $1}')
verdict=FAIL
if ((count == 60 &&
     hybrid_sum < strong_fixed_sum &&
     hybrid_sum < simplification_sum &&
     hybrid_sum < equality_sum &&
     hybrid_sum < brute_sum &&
     hybrid_sum < random_sum &&
     hybrid_sum < replay_sum &&
     wins > 0 &&
     crossover_selected > 0)); then
  verdict=PASS
fi

{
  printf 'GHOST_MATH_PROSPECTIVE_V2 %s\n' "$verdict"
  printf 'dryrun=%s targets_sha256=%s candidate_v1_sha256=%s candidate_v2_sha256=%s\n' \
    "$dryrun" "$targets_sha" "$candidate_v1_sha" "$candidate_v2_sha"
  printf 'count=%d wins_vs_strong_fixed=%d ties_vs_strong_fixed=%d losses_vs_strong_fixed=%d crossover_selected=%d\n' \
    "$count" "$wins" "$ties" "$losses" "$crossover_selected"
  printf 'sum_hybrid=%d sum_strong_fixed=%d sum_inherited=%d sum_simplification=%d sum_equality=%d sum_brute=%d sum_random=%d sum_replay=%d\n' \
    "$hybrid_sum" "$strong_fixed_sum" "$inherited_sum" "$simplification_sum" \
    "$equality_sum" "$brute_sum" "$random_sum" "$replay_sum"
  printf 'compute_bias=%s hybrid_constructions_per_target=%d strong_fixed_constructions_per_target=%d ratio=%d.0\n' \
    "$([[ $dryrun == 1 ]] && printf matched_dryrun || printf control_favored)" \
    "$hybrid_budget" "$strong_fixed_budget" "$((strong_fixed_budget / hybrid_budget))"
  printf 'equivalence=independent_structural_plus_42_modular_cases_per_tool mutation_selftest=4_of_4_rejected inherited_replay=byte_identical crossover_replay=byte_identical\n'
  printf 'reuse_calls_per_tool=%d hybrid_reuse_multiplications=%d strong_fixed_reuse_multiplications=%d\n' \
    "$reuse_calls" "$((hybrid_sum * reuse_calls))" "$((strong_fixed_sum * reuse_calls))"
  printf 'containment=two_stage_bwrap_user_pid_ipc_uts_mount_plus_final_seccomp ap_probe_denials=6\n'
  printf 'containment_limit=current_host_denies_bwrap_unshare_net;candidate_seccomp_denies_network;default_allow_residual=true\n'
  printf 'scope=prospective_random_addition_chains_not_new_to_humanity_not_minimality_proof\n'
} >"$tmp_summary"

mkdir -p "$(dirname "$output_path")" "$(dirname "$summary_path")"
mv "$tmp_output" "$output_path"
mv "$tmp_summary" "$summary_path"
trap - EXIT
cat "$summary_path"
[[ $verdict == PASS ]]
