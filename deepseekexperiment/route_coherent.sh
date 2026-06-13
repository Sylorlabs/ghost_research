#!/bin/bash
cd "$(dirname "$0")"
echo "[$(date +%H:%M:%S)] START coherent route dump (512 tok off8000)" >> overnight_queue.log
ROUTE_DUMP=route_coherent.bin nice -n 5 ./ppl_stack_route 512 61 8000 0 0.10 12 >> route_coherent.log 2>&1
echo "[$(date +%H:%M:%S)] route dump exit=$? -> span analysis" >> overnight_queue.log
python3 span_locality.py route_coherent.bin >> span_locality.log 2>&1
echo "[$(date +%H:%M:%S)] END span-locality exit=$?" >> overnight_queue.log
touch SPAN_DONE
