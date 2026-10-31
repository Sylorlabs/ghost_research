#!/bin/bash
# Chain 8: after E15, dump per-token routing for two coherent contexts and
# measure context-locality / cold-token fraction (E16). 512-token windows for
# a longer locality signal.
cd "$(dirname "$0")"
while [ ! -f E15_DONE ] || [ ! -f SURROGATE_DONE ]; do sleep 60; done
echo "[$(date +%H:%M:%S)] START E16-routedump off8000" >> overnight_queue.log
ROUTE_DUMP=route_off8000.bin ACT_DUMP=acts_T512_off8000.bin nice -n 5 ./ppl_stack_route 512 61 8000 0 0.10 12 >> route_run8000.txt 2>&1
echo "[$(date +%H:%M:%S)] route off8000 exit=$?" >> overnight_queue.log
ROUTE_DUMP=route_off21601.bin nice -n 5 ./ppl_stack_route 512 61 21601 0 0.10 12 >> route_run21601.txt 2>&1
echo "[$(date +%H:%M:%S)] route off21601 exit=$?" >> overnight_queue.log
OMP_NUM_THREADS=4 nice -n 10 python3 e16_context_locality.py route_off8000.bin  e16_results_off8000.txt >> e16_run.log 2>&1
OMP_NUM_THREADS=4 nice -n 10 python3 e16_context_locality.py route_off21601.bin e16_results_off21601.txt >> e16_run.log 2>&1
echo "[$(date +%H:%M:%S)] END E16 exit=$?" >> overnight_queue.log
OMP_NUM_THREADS=6 nice -n 10 python3 e19c_warmup_long.py acts_T512_off8000.bin >> e19c_run.log 2>&1
echo "[$(date +%H:%M:%S)] END E19c exit=$?" >> overnight_queue.log
touch E16_DONE
