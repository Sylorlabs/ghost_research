#!/usr/bin/env bash
# Round AV launcher: shell stages/process-isolates; all analyzer logic is native Zag.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
zag="$root/../zag/zag-poc"
out=${1:-"$root/results/real_local_inventor_trial_round_av_zag.csv"}
tmp=$(mktemp -d /tmp/round-av-zag.XXXXXX)
trap 'rm -rf "$tmp"' EXIT
train="$root/core/src/adapters/invention_engine.zig"
held="$root/core/src/adapters/domain_agi_subsystem_synthesis.zig"
mkdir -p "$tmp/corpus"
cp "$train" "$tmp/corpus/train.zig"
cp "$held" "$tmp/corpus/heldout.zig"
chmod 0444 "$tmp/corpus"/*.zig
"$zag/znc" "$root/sparse_poly_discovery/round_av_raw_scanner.zag" -o "$tmp/raw" --no-zagd --no-analyze >/dev/null
"$zag/znc" "$root/sparse_poly_discovery/round_av_comment_scanner.zag" -o "$tmp/repaired" --no-zagd --no-analyze >/dev/null
expected() { awk 'BEGIN{n=0} {s=$0; sub(/\/\/.*/,"",s); if(s ~ /pub[[:space:]]+fn[[:space:]]/) n++} END{print n}' "$1"; }
worker() { bwrap --unshare-all --die-with-parent --new-session --clearenv --ro-bind /usr /usr --ro-bind /lib /lib --ro-bind /lib64 /lib64 --proc /proc --dev /dev --ro-bind "$tmp/corpus" /work/corpus --ro-bind "$1" /work/analyzer --tmpfs /tmp /work/analyzer "/work/corpus/$2"; }
mkdir -p "$(dirname "$out")"
printf 'ordinal,policy,hypothesis,artifact,artifact_sha256,source_sha256,worker_exit,candidate_output,expected_visible_to_worker,answer_literal_in_source,correct\n' > "$out"
row() { local ordinal=$1 policy=$2 hypothesis=$3 binary=$4 artifact=$5 original=$6; local got rc expected_value source_hash artifact_hash contains correct; set +e; got=$(worker "$binary" "$artifact" 2>/dev/null); rc=$?; set -e; expected_value=$(expected "$original"); source_hash=$(sha256sum "$binary" | awk '{print $1}'); artifact_hash=$(sha256sum "$tmp/corpus/$artifact" | awk '{print $1}'); contains=false; if strings "$binary" | grep -qx "$expected_value"; then contains=true; fi; correct=false; if [ "$rc" = 0 ] && [ "$got" = "$expected_value" ]; then correct=true; fi; printf '%s,%s,%s,%s,%s,%s,%s,%s,false,%s,%s\n' "$ordinal" "$policy" "$hypothesis" "$artifact" "$artifact_hash" "$source_hash" "$rc" "$got" "$contains" "$correct" >> "$out"; }
row 1 candidate_raw raw_token_count "$tmp/raw" train.zig "$train"
row 2 candidate_repaired comments_are_false_positives "$tmp/repaired" train.zig "$train"
row 3 candidate_final sealed_transfer "$tmp/repaired" heldout.zig "$held"
row 4 fixed_comment_scanner fixed_baseline "$tmp/repaired" heldout.zig "$held"
row 5 fixed_raw weak_baseline "$tmp/raw" heldout.zig "$held"
awk -F, 'NR==2&&$11!="false"{exit 1} NR==3&&$11!="true"{exit 1} NR==4&&$11!="true"{exit 1} NR==5&&$11!="true"{exit 1} END{if(NR!=6)exit 1}' "$out"
echo 'round_av_zag PASS native_zag=true real_files=true sandboxed_worker=true repair=true transfer=true strong_fixed_tie=true verdict=OPERATES_BUT_NO_LEARNED_ADVANTAGE'
