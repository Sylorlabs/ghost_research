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
foundation=0
compounding=0
gate_ready=0
blocked=0
live=0
ready=0

while IFS= read -r line; do
    if [[ ! "$line" =~ ^\|[[:space:]]*([A-Z]+[0-9]+)[[:space:]]*\| ]]; then
        continue
    fi
    id=${BASH_REMATCH[1]}

    total=$((total + 1))
    if [[ "$line" == *"**BLOCKED"* || "$line" =~ \|[[:space:]]*blocked[[:space:]] ]]; then
        state=BLOCKED
        blocked=$((blocked + 1))
    elif [[ "$line" == *"**INCONCLUSIVE"* || "$line" == *"VALID NEGATIVE"* || "$line" == *"**INVALIDATED"* ]]; then
        state=TERMINAL_NEGATIVE
        negative=$((negative + 1))
    elif [[ "$line" =~ \|[[:space:]]*ready[[:space:]] || "$line" == *"**READY"* ]]; then
        state=READY
        ready=$((ready + 1))
    elif [[ "$line" == *"**GATE READY"* ]]; then
        state=GATE_READY
        done=$((done + 1))
        gate_ready=$((gate_ready + 1))
    elif [[ "$line" == *"**COMPOUNDING POSITIVE"* ]]; then
        state=COMPOUNDING_POSITIVE
        done=$((done + 1))
        compounding=$((compounding + 1))
    elif [[ "$line" == *"**FOUNDATION POSITIVE"* || "$line" == *"**FOUNDATION PASS"* ]]; then
        state=FOUNDATION_POSITIVE
        done=$((done + 1))
        foundation=$((foundation + 1))
    elif [[ "$line" == *"**DONE"* ]]; then
        state=DONE
        done=$((done + 1))
    else
        state=LIVE
        live=$((live + 1))
    fi
    printf '%s=%s\n' "$id" "$state"
done < "$round_doc"

if (( total == 0 )); then
    printf 'ROUND_STATUS_ERROR: no experiment rows found\n' >&2
    exit 2
fi

printf 'SUMMARY: total=%d done=%d foundation_positive=%d compounding_positive=%d gate_ready=%d terminal_negative=%d ready=%d blocked=%d live=%d\n' \
    "$total" "$done" "$foundation" "$compounding" "$gate_ready" "$negative" "$ready" "$blocked" "$live"

if (( live > 0 || ready > 0 )); then
    printf 'ROUND_SETTLED=NO\nROUND_COMPLETE=NO\n'
    exit 1
fi

printf 'ROUND_SETTLED=YES\n'
if (( blocked > 0 )); then
    printf 'ROUND_COMPLETE=NO (blocked experiments require a new accepted input)\n'
    exit 1
fi

printf 'ROUND_COMPLETE=YES\n'
