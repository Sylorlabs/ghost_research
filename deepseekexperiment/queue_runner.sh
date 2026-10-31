#!/bin/bash
# Detached experiment queue — survives Claude session death, terminal close,
# logout. Launch with:  setsid nohup ./queue_runner.sh > queue_runner.log 2>&1 &
# Progress: tail -f overnight_queue.log ; done marker: QUEUE_DONE
cd "$(dirname "$0")"
LOG=overnight_queue.log
log() { echo "[$(date +%H:%M:%S)] $*" >> "$LOG"; }

# Wait for any in-flight harness run to finish before starting the queue
while pgrep -f "ppl_stack" > /dev/null; do sleep 30; done
log "queue start"

run() { # run <label> <outfile> <cmd...>
    local label=$1 outfile=$2; shift 2
    log "START $label -> $outfile"
    "$@" >> "$outfile" 2>&1
    log "END   $label exit=$?"
}

# Serialized: one heavy job at a time (lesson from 06-12 session death)
run "B2 U2-L30-w1" u2_run_L30_w1.log env OMP_NUM_THREADS=10 nice -n 10 python3 u2_expert_spectrum.py 30 w1
run "A2 eps0.25"   u3_screen_eps25.txt nice -n 5 ./ppl_stack 128 61 8000 128 0.25 12
run "B4 U2-L30-w2" u2_run_L30_w2.log env OMP_NUM_THREADS=10 nice -n 10 python3 u2_expert_spectrum.py 30 w2
run "A3 eps0.05"   u3_screen_eps05.txt nice -n 5 ./ppl_stack 128 61 8000 128 0.05 12
run "B3 U2-L10-w1" u2_run_L10_w1.log env OMP_NUM_THREADS=10 nice -n 10 python3 u2_expert_spectrum.py 10 w1
run "A4 cap256"    u3_screen_cap256.txt nice -n 5 ./ppl_stack 128 61 8000 256 0.10 12
run "A5 wiki-base" e11_wiki_baseline.txt nice -n 5 ./ppl_stack 128 61 21601 0 0.10 12
run "A6 cap8-hyst" u3_screen_cap8.txt nice -n 5 ./ppl_stack 128 61 8000 8 0.10 12
run "A7 wiki-u3"   u3_wiki_cap128.txt nice -n 5 ./ppl_stack 128 61 21601 128 0.10 12
log "queue done"
touch QUEUE_DONE
