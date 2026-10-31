#!/bin/bash
cd "$(dirname "$0")"
while [ ! -f FREQPREC_DONE ]; do sleep 60; done
# decisive: full stack at P2 (2-bit, 1.6x leaner than P3) — does end-to-end quality hold?
echo "[$(date +%H:%M:%S)] START lean P2-global" >> overnight_queue.log
nice -n 5 ./ppl_stack 128 61 8000 0 0.10 12 6 0 2 > lean_P2.txt 2>&1
echo "[$(date +%H:%M:%S)] END lean P2 exit=$?" >> overnight_queue.log
# per-layer: force deepest layers to P1, see how deep we can go lean
echo "[$(date +%H:%M:%S)] START lean-from-40 (layers 40-60 at P1)" >> overnight_queue.log
nice -n 5 ./ppl_stack 128 61 8000 0 0.10 12 6 0 3 40 > lean_from40.txt 2>&1
echo "[$(date +%H:%M:%S)] END lean-from-40 exit=$?" >> overnight_queue.log
echo "[$(date +%H:%M:%S)] START lean-from-30 (layers 30-60 at P1)" >> overnight_queue.log
nice -n 5 ./ppl_stack 128 61 8000 0 0.10 12 6 0 3 30 > lean_from30.txt 2>&1
echo "[$(date +%H:%M:%S)] END lean-from-30 exit=$?" >> overnight_queue.log
touch LEAN_DONE
