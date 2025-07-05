#!/bin/bash

# Accept zone name as first argument, or use environment variable, or default
CDC_JOINED_ZONE=${CDC_JOINED_ZONE:-"UNKNOWN"}

if [ "$CDC_JOINED_ZONE" == "UNKNOWN" ]; then
    SUBNET=$(ifconfig | fgrep -C 1 bondpriv | fgrep inet | awk '{print $2}' | cut -f-2 -d.)
    if [ "$SUBNET" == "10.0" ]; then
        CLUSTER=JUNO
    else
        CLUSTER="UNKNOWN"
    fi
else
    ZONE=$(echo $CDC_JOINED_ZONE | tr ',' '\n' | fgrep CN= | fgrep -iv zone | head -1)
    if [ "$ZONE" != "" ]; then
        CLUSTER=$(echo $ZONE | cut -f2 -d=)
    else
        CLUSTER="UNKNOWN"
    fi
fi

