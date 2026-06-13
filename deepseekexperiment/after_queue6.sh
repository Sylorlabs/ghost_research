#!/bin/bash
# Chain 7: after the forge, run E15 functional-dedup long-shot (5 min).
cd "$(dirname "$0")"
while [ ! -f FORGE_DONE ]; do sleep 60; done
echo "[$(date +%H:%M:%S)] START E15 func-dedup" >> overnight_queue.log
OMP_NUM_THREADS=10 nice -n 10 python3 e15_expert_funcdedup.py >> e15_run.log 2>&1
echo "[$(date +%H:%M:%S)] END E15 exit=$?" >> overnight_queue.log
touch E15_DONE
