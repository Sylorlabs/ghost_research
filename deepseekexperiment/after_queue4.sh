#!/bin/bash
# Chain 5: pure-hysteresis at higher eps — is recency-substitution alone a
# stronger quality repair when pushed?
cd "$(dirname "$0")"
while [ ! -f EPS40_DONE ]; do sleep 60; done
echo "[$(date +%H:%M:%S)] START A11 cap8-eps0.25" >> overnight_queue.log
nice -n 5 ./ppl_stack 128 61 8000 8 0.25 12 >> u3_screen_cap8_eps25.txt 2>&1
echo "[$(date +%H:%M:%S)] END A11 cap8-eps0.25 exit=$?" >> overnight_queue.log
touch HYST_DONE
