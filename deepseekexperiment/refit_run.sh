#!/bin/bash
cd "$(dirname "$0")"
while pgrep -f "ppl_stack 128 61 8000" >/dev/null; do sleep 30; done
for RA in 2 4; do
  echo "[$(date +%H:%M:%S)] START refit_alt=$RA" >> overnight_queue.log
  nice -n 5 ./ppl_stack 128 61 8000 0 0.10 12 6 0 3 61 8 $RA > refit_${RA}.txt 2>&1
  echo "[$(date +%H:%M:%S)] END refit_alt=$RA exit=$?" >> overnight_queue.log
done
touch REFIT_DONE
