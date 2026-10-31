#!/bin/bash
# Chain 3: after the controls finish, dump big activation corpora (ref-stream
# gate/expert inputs) from two text domains, then rerun the B5 manifold
# analysis on the larger corpus. Survives session death.
cd "$(dirname "$0")"
LOG=overnight_queue.log
while [ ! -f CONTROLS_DONE ]; do sleep 60; done
echo "[$(date +%H:%M:%S)] act-dump chain start" >> "$LOG"
ACT_DUMP=acts_T128_off8000.bin nice -n 5 ./ppl_stack_actdump 128 61 8000 0 0.10 12 >> actdump_off8000.txt 2>&1
echo "[$(date +%H:%M:%S)] END D1 actdump-8000 exit=$?" >> "$LOG"
ACT_DUMP=acts_T128_off21601.bin nice -n 5 ./ppl_stack_actdump 128 61 21601 0 0.10 12 >> actdump_off21601.txt 2>&1
echo "[$(date +%H:%M:%S)] END D2 actdump-21601 exit=$?" >> "$LOG"
cat acts_T128_off8000.bin acts_T128_off21601.bin > acts_combined.bin
OMP_NUM_THREADS=10 nice -n 10 python3 b5_activation_manifold.py acts_combined.bin b5_results_v2.txt >> b5_v2_run.log 2>&1
echo "[$(date +%H:%M:%S)] END D3 b5-v2 exit=$?" >> "$LOG"
touch ACTDUMP_DONE
