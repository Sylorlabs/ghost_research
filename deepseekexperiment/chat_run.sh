#!/bin/bash
cd "$(dirname "$0")"
echo "[$(date +%H:%M:%S)] START chat_v4 first prediction" >> overnight_queue.log
nice -n 5 ./chat_v4 128 61 0 0 0.10 12 > chat_v4_out.txt 2>&1
echo "[$(date +%H:%M:%S)] END chat_v4 exit=$?" >> overnight_queue.log
touch CHAT_DONE
