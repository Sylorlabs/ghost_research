#!/bin/bash
cd "$(dirname "$0")"
echo "[$(date +%H:%M:%S)] START surrogate capture (512 tok, layers 0-30, off8000)" >> overnight_queue.log
ACT_DUMP=acts_long_off8000.bin nice -n 5 ./ppl_stack_route 512 31 8000 0 0.10 8 >> try_capture.log 2>&1
echo "[$(date +%H:%M:%S)] capture done exit=$? -> running E19c" >> overnight_queue.log
OMP_NUM_THREADS=6 nice -n 8 python3 e19c_warmup_long.py acts_long_off8000.bin >> e19c_run.log 2>&1
echo "[$(date +%H:%M:%S)] END E19c-long exit=$?" >> overnight_queue.log
touch SURROGATE_DONE
