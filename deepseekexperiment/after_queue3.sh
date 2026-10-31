#!/bin/bash
# Chain 4: after act-dumps, probe the aggressive end of the eps frontier.
cd "$(dirname "$0")"
while [ ! -f ACTDUMP_DONE ]; do sleep 60; done
echo "[$(date +%H:%M:%S)] START A10 eps0.40" >> overnight_queue.log
nice -n 5 ./ppl_stack 128 61 8000 128 0.40 12 >> u3_screen_eps40.txt 2>&1
echo "[$(date +%H:%M:%S)] END A10 eps0.40 exit=$?" >> overnight_queue.log
touch EPS40_DONE
