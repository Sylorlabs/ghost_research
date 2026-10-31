#!/bin/bash
# Chained controls: wait for the main queue, then run the T=128 anchors the
# screening comparisons need (no-policy baseline + cap=64 at same T).
cd "$(dirname "$0")"
LOG=overnight_queue.log
while [ ! -f QUEUE_DONE ]; do sleep 60; done
echo "[$(date +%H:%M:%S)] after-queue controls start" >> "$LOG"
nice -n 5 ./ppl_stack 128 61 8000 0 0.10 12 >> e11_T128_off8000_baseline.txt 2>&1
echo "[$(date +%H:%M:%S)] END A8 T128-baseline exit=$?" >> "$LOG"
nice -n 5 ./ppl_stack 128 61 8000 64 0.10 12 >> u3_screen_cap64_T128.txt 2>&1
echo "[$(date +%H:%M:%S)] END A9 cap64-T128 exit=$?" >> "$LOG"
touch CONTROLS_DONE
