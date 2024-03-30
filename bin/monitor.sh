#!/bin/bash

II=1
while [ 1 ]; do
    w | fgrep averag | tee -a W.log;
    ps -eo pid,user,cmd | fgrep socci | egrep -wv "sshd|grep|bash|ps|wc|tee" | tee PS.${II}.log | wc -l | tee -a PSN.log;
    sleep 30
    II=$((II+1))
done
