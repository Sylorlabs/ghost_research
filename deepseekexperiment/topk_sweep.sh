#!/bin/bash
cd "$(dirname "$0")"
for K in 6 4 3 2; do
  echo "[$(date +%H:%M:%S)] START topk=$K" >> overnight_queue.log
  nice -n 5 ./ppl_stack 128 61 8000 0 0.10 12 $K > topk_${K}.txt 2>&1
  echo "[$(date +%H:%M:%S)] END topk=$K exit=$?" >> overnight_queue.log
done
touch TOPK_DONE
