#!/bin/bash
cd "$(dirname "$0")"
for N in 64 32; do
  echo "[$(date +%H:%M:%S)] START freq-precision top-$N" >> overnight_queue.log
  nice -n 5 ./ppl_stack 128 61 8000 0 0.10 12 6 $N > freqprec_${N}.txt 2>&1
  echo "[$(date +%H:%M:%S)] END freq-precision top-$N exit=$?" >> overnight_queue.log
done
touch FREQPREC_DONE
