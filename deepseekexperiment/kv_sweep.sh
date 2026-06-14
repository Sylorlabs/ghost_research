#!/bin/bash
cd "$(dirname "$0")"
for KV in 4 3; do
  echo "[$(date +%H:%M:%S)] START kv_bits=$KV" >> overnight_queue.log
  nice -n 5 ./ppl_stack 128 61 8000 0 0.10 12 6 0 3 61 $KV > kv_${KV}.txt 2>&1
  echo "[$(date +%H:%M:%S)] END kv_bits=$KV exit=$?" >> overnight_queue.log
done
touch KV_DONE
