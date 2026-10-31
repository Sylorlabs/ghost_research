#!/bin/bash
# Chain 6: after all experiments, forge the full engine core on ext4.
cd "$(dirname "$0")"
while [ ! -f HYST_DONE ]; do sleep 60; done
echo "[$(date +%H:%M:%S)] START FORGE full core" >> overnight_queue.log
nice -n 5 ./forge engine_weights 61 >> forge_full.log 2>&1
echo "[$(date +%H:%M:%S)] END FORGE exit=$?" >> overnight_queue.log
nice -n 5 ./forge verify engine_weights >> forge_full.log 2>&1
echo "[$(date +%H:%M:%S)] END FORGE-verify exit=$?" >> overnight_queue.log
touch FORGE_DONE
