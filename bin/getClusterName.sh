#!/bin/bash

# This script needs to be sourced not run
# to work properly
#
if [[ "$0" == "${BASH_SOURCE[0]}" ]]; then
    echo -e "\n  This will not work if run directly"
    echo -e "  It needs to be sourced\n"
    exit 1
fi

# Function to get network subnet from interface configuration
get_network_subnet() {
    ifconfig 2>/dev/null | \
        fgrep -w inet | \
        fgrep -v 127.0.0.1 | \
        fgrep 10. | \
        head -1 | \
        awk '{print $2}' | \
        cut -f-2 -d.
}

# Function to extract zone from CDC_JOINED_ZONE
get_zone() {
    local cdc_zone="$1"
    echo "$cdc_zone" | \
        tr ',' '\n' | \
        fgrep CN= | \
        fgrep -iv zone | \
        head -1
}

# Accept zone name as first argument, or use environment variable, or default
CDC_JOINED_ZONE=${CDC_JOINED_ZONE:-"UNKNOWN"}

if [ "$CDC_JOINED_ZONE" == "UNKNOWN" ]; then
    SUBNET=$(get_network_subnet)
    if [ "$SUBNET" == "10.0" ]; then
        CLUSTER=JUNO
    else
        CLUSTER="UNKNOWN"
    fi
else
    ZONE=$(get_zone "$CDC_JOINED_ZONE")
    if [ "$ZONE" != "" ]; then
        CLUSTER=$(echo $ZONE | cut -f2 -d=)
    else
        CLUSTER="UNKNOWN"
    fi
fi
