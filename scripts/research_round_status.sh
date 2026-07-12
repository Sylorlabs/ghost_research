#!/usr/bin/env bash
# Report the authoritative state of a research wave from its master ledger.
# Exit 0: every experiment is terminal and none is blocked.
# Exit 1: one or more experiments is still live or blocked.
set -euo pipefail

round_doc=${1:-docs/research/research_round_2026_07_11c.md}

if [[ ! -f "$round_doc" ]]; then
    printf 'ROUND_STATUS_ERROR: master document not found: %s\n' "$round_doc" >&2
    exit 2
fi

printf 'ROUND_STATUS: %s\n' "$round_doc"

total=0
done=0
negative=0
blocked=0
live=0

for id in G1 G2 G3 G4 G5; do
    line=$(rg -m1 "^\\| ${id} \\|" "$round_doc" || true)
    if [[ -z "$line" ]]; then
        continue
    fi

    total=$((total + 1))
    if [[ "$line" == *"**BLOCKED"* ]]; then
        state=BLOCKED
        blocked=$((blocked + 1))
    elif [[ "$line" == *"**INCONCLUSIVE"* || "$line" == *"**VALID NEGATIVE"* ]]; then
        state=TERMINAL_NEGATIVE
        negative=$((negative + 1))
    elif [[ "$line" == *"**DONE"* ]]; then
        state=DONE
        done=$((done + 1))
    else
        state=LIVE
        live=$((live + 1))
    fi
    printf '%s=%s\n' "$id" "$state"
done

printf 'SUMMARY: total=%d done=%d terminal_negative=%d blocked=%d live=%d\n' \
    "$total" "$done" "$negative" "$blocked" "$live"

if (( live > 0 )); then
    printf 'ROUND_SETTLED=NO\nROUND_COMPLETE=NO\n'
    exit 1
fi

printf 'ROUND_SETTLED=YES\n'
if (( blocked > 0 )); then
    printf 'ROUND_COMPLETE=NO (blocked experiments require a new accepted input)\n'
    exit 1
fi

printf 'ROUND_COMPLETE=YES\n'
