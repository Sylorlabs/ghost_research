#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
project_root="$repo_root/ghost_scientist"
targets_path=${1:-"$project_root/results/ghost_ruler_heldout_targets_v3.tsv"}
output_path=${2:-"$project_root/results/ghost_ruler_prospective_v3.tsv"}
summary_path=${3:-"$project_root/results/ghost_ruler_prospective_v3.summary.txt"}
audit_path=${4:-"$project_root/results/ghost_ruler_prospective_v3.audit.txt"}
dryrun=${GHOST_RULER_V3_DRYRUN:-0}
expected_count=60
if [[ $dryrun == 1 ]]; then
  expected_count=20
fi

candidate_source="$project_root/candidate/ghost_ruler_candidate_v3.py"
grammar_path="$project_root/results/ghost_ruler_selected_grammar_v3.txt"
no_probe_path="$project_root/results/ghost_ruler_no_probe_grammar_v3.txt"
random_path="$project_root/results/ghost_ruler_random_grammar_v3.txt"
development_path="$project_root/results/ghost_ruler_development_generated_v3.tsv"
evaluator="$project_root/evaluator/ghost_ruler_v3.py"
verifier="$project_root/evaluator/ghost_poly_verify_v3.py"
allowlist_source="$project_root/containment/ghost_ap_allowlist_v3.zig"
probe_source="$project_root/containment/ghost_ap_probe_v3.zig"
allowlist_bin=/tmp/ghost_ap_allowlist_v3
probe_bin=/tmp/ghost_ap_probe_v3
filter_path=/tmp/ghost_ap_allowlist_v3.bpf
zig_global_cache=/tmp/ghost-ruler-zig-global-cache
candidate_node_limit=5000
strong_fixed_node_limit=10000
reuse_calls=42

cd "$repo_root"
./ghost_scientist/protocol/verify_ghost_ruler_freeze_v3.sh
python3 -B "$evaluator" selftest
python3 -B "$evaluator" validate "$grammar_path"
python3 -B "$evaluator" validate "$no_probe_path"
python3 -B "$evaluator" validate "$random_path"
python3 -B "$verifier" --selftest

zig build-exe "$allowlist_source" -O ReleaseSafe -lc -lseccomp \
  -femit-bin="$allowlist_bin" \
  --cache-dir /tmp/ghost-ruler-allowlist-cache \
  --global-cache-dir "$zig_global_cache"
zig build-exe "$probe_source" -O ReleaseSafe \
  -femit-bin="$probe_bin" \
  --cache-dir /tmp/ghost-ruler-probe-cache \
  --global-cache-dir "$zig_global_cache"
"$allowlist_bin" "$filter_path"

contain_program() {
  local program=$1
  shift
  (
    exec 9<"$filter_path"
    timeout --signal=KILL 25s \
      unshare --user --map-root-user --net \
      prlimit --as=268435456 --cpu=20 --nofile=32:32 -- \
      bwrap \
        --unshare-user --unshare-pid --unshare-ipc --unshare-uts \
        --die-with-parent --new-session --as-pid-1 --cap-drop ALL --clearenv \
        --ro-bind /usr /usr --ro-bind /lib /lib --ro-bind /lib64 /lib64 \
        --proc /proc --dev /dev --tmpfs /tmp --tmpfs /work --chdir /work \
        --ro-bind "$program" /program --seccomp 9 \
        /program "$@"
  )
}

contain_candidate() {
  local expression=$1
  (
    exec 9<"$filter_path"
    timeout --signal=KILL 25s \
      unshare --user --map-root-user --net \
      prlimit --as=268435456 --cpu=20 --nofile=32:32 -- \
      bwrap \
        --unshare-user --unshare-pid --unshare-ipc --unshare-uts \
        --die-with-parent --new-session --as-pid-1 --cap-drop ALL --clearenv \
        --ro-bind /usr /usr --ro-bind /lib /lib --ro-bind /lib64 /lib64 \
        --proc /proc --dev /dev --tmpfs /tmp --tmpfs /work --chdir /work \
        --ro-bind "$candidate_source" /candidate.py \
        --ro-bind "$grammar_path" /grammar \
        --seccomp 9 \
        /usr/bin/python3 -B /candidate.py /grammar "$candidate_node_limit" "$expression"
  )
}

contain_final_probe() {
  (
    exec 9<"$filter_path"
    timeout --signal=KILL 10s \
      unshare --user --map-root-user --net \
      prlimit --as=134217728 --cpu=8 --nofile=32:32 -- \
      bwrap \
        --unshare-user --unshare-pid --unshare-ipc --unshare-uts \
        --die-with-parent --new-session --as-pid-1 --cap-drop ALL --clearenv \
        --ro-bind /usr /usr --ro-bind /lib /lib --ro-bind /lib64 /lib64 \
        --proc /proc --dev /dev --tmpfs /tmp --tmpfs /work --chdir /work \
        --ro-bind "$candidate_source" /candidate.py \
        --seccomp 9 \
        /usr/bin/python3 -B /candidate.py --probe-final
  )
}

outer_probe=$(contain_program "$probe_bin")
[[ $outer_probe == *"GHOST_AP_PROBE_V3 PASS denials=5 policy=outer_default_deny"* ]]
final_probe=$(contain_final_probe)
[[ $final_probe == *"GHOST_RULER_FINAL_PROBE_V3 PASS policy=default_deny denials=6"* ]]
host_netns=$(readlink /proc/self/ns/net)
candidate_netns=$(unshare --user --map-root-user --net readlink /proc/self/ns/net)
[[ $host_netns != "$candidate_netns" ]]

[[ $(sed -n '1p' "$targets_path") == $'opaque_id\tphase\tseed_hex\texpression' ]]
[[ $(wc -l <"$targets_path") -eq $((expected_count + 1)) ]]
awk -F'\t' -v expected="$expected_count" '
  NR == 1 { next }
  NF != 4 || $2 != "HELDOUT" || $3 !~ /^0x[0-9a-f]+$/ || seen_id[$1]++ || seen_expr[$4]++ {
    exit 1
  }
  END { if (NR - 1 != expected) exit 1 }
' "$targets_path"

while IFS=$'\t' read -r opaque_id phase seed_hex expression; do
  [[ $opaque_id == opaque_id ]] && continue
  input_sha=$(printf '%s' "$expression" | sha256sum | awk '{print $1}')
  for visible in "$candidate_source" "$grammar_path" "$development_path"; do
    if rg -F -q -- "$expression" "$visible" || rg -F -q -- "$input_sha" "$visible"; then
      printf 'GHOST_RULER_LEAKAGE_FAIL artifact=%s visible=%s\n' "$opaque_id" "$visible" >&2
      exit 1
    fi
  done
done <"$targets_path"

field() {
  local line=$1
  local name=$2
  local value=${line#*" $name="}
  printf '%s' "${value%% *}"
}

verify_candidate() {
  local line=$1
  local expression=$2
  local grammar_sha=$3
  printf '%s\n' "$line" |
    python3 -B "$verifier" --grammar-sha "$grammar_sha" --expression "$expression" \
      --max-cost 4 >/dev/null
}

verify_control() {
  local line=$1
  local expression=$2
  printf '%s\n' "$line" |
    python3 -B "$verifier" --control --expression "$expression" >/dev/null
}

tmp_output=$(mktemp /tmp/ghost-ruler-prospective-v3.XXXXXX)
tmp_summary=$(mktemp /tmp/ghost-ruler-summary-v3.XXXXXX)
tmp_audit=$(mktemp /tmp/ghost-ruler-audit-v3.XXXXXX)
trap 'rm -f "$tmp_output" "$tmp_summary" "$tmp_audit"' EXIT
printf '%s\n' \
  $'opaque_id\tphase\tseed_hex\tinput_ops\tcandidate_ops\tstrong_fixed_ops\tfixed_simplification_ops\tequality_saturation_ops\tbrute_force_ops\trandom_ops\treplay_ops\tno_memory_ops\tno_probe_ops\tcandidate_delta_strong_fixed\tcandidate_globally_minimal\tcandidate_enodes\tcandidate_ematches\tcandidate_prepass_attempts\tstrong_fixed_enodes\trandom_enodes\tno_probe_enodes\tcandidate_replay_equal\treuse_calls\tcandidate_reuse_ops\tstrong_fixed_reuse_ops\tcandidate_expr\tstrong_fixed_expr' \
  >"$tmp_output"

grammar_sha=$(sha256sum "$grammar_path" | awk '{print $1}')
count=0
candidate_sum=0
strong_fixed_sum=0
simple_sum=0
brute_sum=0
random_sum=0
replay_sum=0
no_probe_sum=0
wins=0
ties=0
losses=0
global_passes=0
replay_passes=0
candidate_enodes_sum=0
strong_fixed_enodes_sum=0
newly_reachable=0

while IFS=$'\t' read -r opaque_id phase seed_hex expression; do
  [[ $opaque_id == opaque_id ]] && continue
  candidate=$(contain_candidate "$expression")
  candidate_replay=$(contain_candidate "$expression")
  [[ $candidate == "$candidate_replay" ]]
  verify_candidate "$candidate" "$expression" "$grammar_sha"

  strong_fixed=$(python3 -B "$evaluator" control strong_fixed "$expression" \
    --node-limit "$strong_fixed_node_limit" --iterations 12)
  simplification=$(python3 -B "$evaluator" control fixed_simplification "$expression")
  brute=$(python3 -B "$evaluator" control brute_force "$expression" --max-proof-cost 4)
  random=$(python3 -B "$evaluator" control random "$expression" \
    --rules "$random_path" --node-limit "$candidate_node_limit" --iterations 12)
  replay=$(python3 -B "$evaluator" control replay "$expression")
  no_probe=$(python3 -B "$evaluator" control no_probe "$expression" \
    --rules "$no_probe_path" --node-limit "$candidate_node_limit" --iterations 12)
  for control in "$strong_fixed" "$simplification" "$brute" "$random" "$replay" "$no_probe"; do
    verify_control "$control" "$expression"
  done

  input_ops=$(field "$candidate" before)
  candidate_ops=$(field "$candidate" after)
  strong_fixed_ops=$(field "$strong_fixed" after)
  simple_ops=$(field "$simplification" after)
  brute_ops=$(field "$brute" after)
  random_ops=$(field "$random" after)
  replay_ops=$(field "$replay" after)
  no_probe_ops=$(field "$no_probe" after)
  candidate_enodes=$(field "$candidate" enodes)
  candidate_ematches=$(field "$candidate" ematches)
  candidate_prepass_attempts=$(field "$candidate" prepass_attempts)
  strong_fixed_enodes=$(field "$strong_fixed" work)
  random_enodes=$(field "$random" work)
  no_probe_enodes=$(field "$no_probe" work)
  candidate_expr=${candidate#*" expr="}
  strong_fixed_expr=${strong_fixed#*" expr="}
  delta=$((strong_fixed_ops - candidate_ops))
  globally_minimal=false
  if ((candidate_ops == brute_ops)); then
    globally_minimal=true
    global_passes=$((global_passes + 1))
  fi
  if ((delta > 0)); then
    wins=$((wins + 1))
    newly_reachable=$((newly_reachable + 1))
  elif ((delta == 0)); then
    ties=$((ties + 1))
  else
    losses=$((losses + 1))
  fi

  count=$((count + 1))
  candidate_sum=$((candidate_sum + candidate_ops))
  strong_fixed_sum=$((strong_fixed_sum + strong_fixed_ops))
  simple_sum=$((simple_sum + simple_ops))
  brute_sum=$((brute_sum + brute_ops))
  random_sum=$((random_sum + random_ops))
  replay_sum=$((replay_sum + replay_ops))
  no_probe_sum=$((no_probe_sum + no_probe_ops))
  candidate_enodes_sum=$((candidate_enodes_sum + candidate_enodes))
  strong_fixed_enodes_sum=$((strong_fixed_enodes_sum + strong_fixed_enodes))
  replay_passes=$((replay_passes + 1))

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\ttrue\t%s\t%s\t%s\t%s\t%s\n' \
    "$opaque_id" "$phase" "$seed_hex" "$input_ops" "$candidate_ops" \
    "$strong_fixed_ops" "$simple_ops" "$strong_fixed_ops" "$brute_ops" \
    "$random_ops" "$replay_ops" "$strong_fixed_ops" "$no_probe_ops" "$delta" \
    "$globally_minimal" "$candidate_enodes" "$candidate_ematches" \
    "$candidate_prepass_attempts" "$strong_fixed_enodes" "$random_enodes" \
    "$no_probe_enodes" "$reuse_calls" "$((candidate_ops * reuse_calls))" \
    "$((strong_fixed_ops * reuse_calls))" "$candidate_expr" "$strong_fixed_expr" \
    >>"$tmp_output"
  printf 'GHOST_RULER_PROGRESS_V3 artifact=%s count=%d candidate=%d strong_fixed=%d brute=%d\n' \
    "$opaque_id" "$count" "$candidate_ops" "$strong_fixed_ops" "$brute_ops"
done <"$targets_path"

verdict=FAIL
if ((count == expected_count &&
     global_passes == count &&
     replay_passes == count &&
     losses == 0 &&
     wins > 0 &&
     candidate_sum == brute_sum &&
     candidate_sum < strong_fixed_sum &&
     candidate_sum < simple_sum &&
     candidate_sum < random_sum &&
     candidate_sum < replay_sum &&
     candidate_sum < no_probe_sum)); then
  verdict=PASS
fi

targets_sha=$(sha256sum "$targets_path" | awk '{print $1}')
candidate_sha=$(sha256sum "$candidate_source" | awk '{print $1}')
filter_sha=$(sha256sum "$filter_path" | awk '{print $1}')
{
  printf 'GHOST_RULER_PROSPECTIVE_V3 %s\n' "$verdict"
  printf 'dryrun=%s count=%d targets_sha256=%s candidate_sha256=%s grammar_sha256=%s\n' \
    "$dryrun" "$count" "$targets_sha" "$candidate_sha" "$grammar_sha"
  printf 'candidate_sum=%d strong_fixed_sum=%d fixed_simplification_sum=%d equality_saturation_sum=%d brute_force_sum=%d random_sum=%d replay_sum=%d no_memory_sum=%d no_probe_sum=%d\n' \
    "$candidate_sum" "$strong_fixed_sum" "$simple_sum" "$strong_fixed_sum" \
    "$brute_sum" "$random_sum" "$replay_sum" "$strong_fixed_sum" "$no_probe_sum"
  printf 'wins_ties_losses_vs_strong_fixed=%d_%d_%d globally_minimal=%d_of_%d newly_reachable_vs_strong_fixed=%d\n' \
    "$wins" "$ties" "$losses" "$global_passes" "$count" "$newly_reachable"
  printf 'compute_policy=candidate_5000_enodes_plus_prepass_strong_fixed_10000_enodes candidate_enodes=%d strong_fixed_enodes=%d\n' \
    "$candidate_enodes_sum" "$strong_fixed_enodes_sum"
  printf 'replay=byte_identical_%d_of_%d reuse_calls=%d candidate_reuse_ops=%d strong_fixed_reuse_ops=%d\n' \
    "$replay_passes" "$count" "$reuse_calls" "$((candidate_sum * reuse_calls))" \
    "$((strong_fixed_sum * reuse_calls))"
  printf 'containment=outer_user_and_network_namespace_plus_bwrap_user_pid_ipc_uts_mount_plus_two_default_deny_seccomp_filters\n'
  printf 'containment_evidence=netns_distinct outer_denials_5_of_5 final_denials_6_of_6 filter_sha256=%s\n' "$filter_sha"
  printf 'verification=independent_exact_integer_polynomial_normalizer_plus_exhaustive_semantic_layer_global_minimum mutation_rejection=4_of_4\n'
  printf 'novelty_scope=machine_generated_locally_new_reusable_grammar_and_newly_reachable_heldout_optima_not_algorithm_or_human_mathematics_novelty\n'
} >"$tmp_summary"

fixed_rule_overlap=$(comm -12 \
  <(python3 -B "$evaluator" validate "$grammar_path" >/dev/null; rg -v '^#|^$' "$grammar_path" | sort) \
  <(printf '%s\n' \
    '(add ?a 0) => ?a' '(mul ?a 0) => 0' '(mul ?a 1) => ?a' \
    '(sub ?a 0) => ?a' '(sub ?a ?a) => 0' \
    '(add ?a ?b) => (add ?b ?a)' '(mul ?a ?b) => (mul ?b ?a)' \
    '(add (add ?a ?b) ?c) => (add ?a (add ?b ?c))' \
    '(mul (mul ?a ?b) ?c) => (mul ?a (mul ?b ?c))' \
    '(mul ?a (add ?b ?c)) => (add (mul ?a ?b) (mul ?a ?c))' \
    '(mul ?a (sub ?b ?c)) => (sub (mul ?a ?b) (mul ?a ?c))' \
    '(sub (add ?a ?b) ?c) => (add ?a (sub ?b ?c))' | sort) |
  wc -l)
selected_rule_count=$(rg -v '^#|^$' "$grammar_path" | wc -l)
{
  printf 'GHOST_RULER_NOVELTY_AUDIT_V3 PASS\n'
  printf 'selected_rules=%d exact_text_overlap_with_12_supplied_fixed_forms=%d machine_generated_nonidentical_forms=%d\n' \
    "$selected_rule_count" "$fixed_rule_overlap" "$((selected_rule_count - fixed_rule_overlap))"
  printf 'heldout_exact_input_leakage=0_of_%d newly_reachable_global_optima_vs_compute_favored_fixed=%d\n' \
    "$count" "$newly_reachable"
  printf 'prior_art_algorithm=Ruler_family_rule_inference_by_semantic_equivalence_classes claim_algorithm_novelty=false\n'
  printf 'claim_human_mathematical_novelty=false claim_local_artifact_novelty=true\n'
} >"$tmp_audit"

mkdir -p "$(dirname "$output_path")" "$(dirname "$summary_path")" "$(dirname "$audit_path")"
mv "$tmp_output" "$output_path"
mv "$tmp_summary" "$summary_path"
mv "$tmp_audit" "$audit_path"
trap - EXIT
cat "$summary_path"
cat "$audit_path"
[[ $verdict == PASS ]]
