#!/bin/bash

# This script needs to be sourced not run
# to work properly
#
if [[ "$0" == "${BASH_SOURCE[0]}" ]]; then
    echo -e "\n  This will not work if run directly"
    echo -e "  It needs to be sourced\n"
    exit 1
fi

# Function to extract zone from CDC_JOINED_ZONE
# Parses comma-separated CDC_JOINED_ZONE string to find CN= entries
# Parameters: $1 - CDC_JOINED_ZONE string to parse
# Returns: First CN= entry excluding those containing "zone" (case-insensitive)
get_zone() {
    local cdc_zone="$1"
    
    # Validate input parameter
    if [[ -z "$cdc_zone" ]]; then
        return 1
    fi
    
    echo "$cdc_zone" | \
        tr ',' '\n' | \
        fgrep CN= | \
        fgrep -iv zone | \
        head -1
}

# Debug output function - only outputs if DEBUG_CLUSTER is set
debug_log() {
    if [[ -n "$DEBUG_CLUSTER" ]]; then
        echo "[DEBUG] $*" >&2
    fi
}

# Main function to determine cluster name from CDC_JOINED_ZONE
# Sets global CLUSTER variable with detected cluster name (IRIS sets
# CDC_JOINED_ZONE); UNKNOWN when it is not set
determine_cluster() {
    local cdc_zone="${CDC_JOINED_ZONE:-UNKNOWN}"

    debug_log "Starting cluster determination with CDC_JOINED_ZONE='$cdc_zone'"

    if [[ "$cdc_zone" == "UNKNOWN" ]]; then
        CLUSTER="UNKNOWN"
        debug_log "CDC_JOINED_ZONE not set, setting CLUSTER=UNKNOWN"
    else
        debug_log "Using CDC_JOINED_ZONE method"
        local zone
        zone=$(get_zone "$cdc_zone")
        debug_log "Extracted zone: '$zone'"
        
        if [[ -n "$zone" ]]; then
            CLUSTER=$(echo "$zone" | cut -f2 -d=)
            debug_log "Zone found, setting CLUSTER='$CLUSTER'"
        else
            CLUSTER="UNKNOWN"
            debug_log "No valid zone found, setting CLUSTER=UNKNOWN"
        fi
    fi
    
    debug_log "Final CLUSTER value: '$CLUSTER'"
}

# Determine cluster name
determine_cluster
