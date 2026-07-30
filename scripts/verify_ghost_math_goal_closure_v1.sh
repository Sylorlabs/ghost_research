#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

check_hash() {
  local expected=$1
  local path=$2
  local actual
  actual=$(sha256sum "$path" | awk '{print $1}')
  [[ $actual == "$expected" ]] || {
    printf 'GOAL_CLOSURE_MISMATCH %s expected=%s actual=%s\n' \
      "$path" "$expected" "$actual" >&2
    exit 1
  }
  printf 'GOAL_CLOSURE_OK %s %s\n' "$actual" "$path"
}

check_line() {
  local line=$1
  grep -Fqx -- "$line" results/ghost_math_goal_closure_v1.txt || {
    printf 'GOAL_CLOSURE_CLAIM_MISSING %s\n' "$line" >&2
    exit 1
  }
}

check_hash a3fb77b1e55331f854eff9795bcf8f6350b95ed1156193c89f6827a990160d80 \
  results/ghost_math_goal_closure_v1.txt
check_hash e89b3f3e5ad3e7817d32f3da049c7922ce457db2c3d617c3c757eec13d5147b9 \
  docs/research/ghost_scientist_outcome_math.md
check_hash 5e5a0b398dad5ff8493661f7928103b65062dbd270317c67b3d98289a0693ee1 \
  results/ghost_math_prospective_v1_attestation.txt
check_hash 095b0566b6e02cc74bc76cf338f87b660b6993a343918e8b60b5552ffe21b730 \
  scripts/verify_ghost_math_prospective_v1_attestation.sh
check_hash ed0f43857402b9672c9373c4662a4e59be35d0e6626737a730d8bf0b2f6f86db \
  results/ghost_math_prospective_v2_attestation.txt
check_hash 101d03e1982fc901895d362ca4cbe6ceae38d347b7310c80ee8f84b5251b88a4 \
  scripts/verify_ghost_math_prospective_v2_attestation.sh

check_line 'v1_verdict=PROSPECTIVE_NEGATIVE_NO_GENERALIZATION'
check_line 'v2_verdict=PROSPECTIVE_POSITIVE_CROSSOVER_GENERALIZED_ON_FRESH_BATCH'
check_line 'v2_wins_ties_losses_vs_compute_favored_strong_fixed=9_51_0'
check_line 'v2_sum_hybrid_vs_strong_fixed=2364_2373'
check_line 'v2_constructions_per_target_hybrid_vs_strong_fixed=48000_96000'
check_line 'v2_reuse_multiplication_saving=378'
check_line 'mutation=4_of_4_rejected'
check_line 'grammar_claim=one_generic_agent_authored_crossover_grammar_constructs_one_target_specific_tool_not_autonomous_primitive_grammar_invention'
check_line 'equality_claim=bounded_radix_horner_saturation_proxy_not_general_external_egraph'
check_line 'scientific_claim=valid_comparative_addition_chains_not_global_minimality_not_new_to_humanity'
check_line 'containment_limit=host_denied_bwrap_unshare_net_and_seccomp_is_default_allow_for_unlisted_syscalls'
check_line 'goal_verdict=BOUNDED_PROSPECTIVE_POSITIVE_AFTER_PRESERVED_NEGATIVE'

scripts/verify_ghost_math_prospective_v1_attestation.sh
scripts/verify_ghost_math_prospective_v2_attestation.sh

printf 'GHOST_MATH_GOAL_CLOSURE_V1 PASS verdict=BOUNDED_PROSPECTIVE_POSITIVE_AFTER_PRESERVED_NEGATIVE\n'
