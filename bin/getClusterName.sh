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
# Uses modern 'ip' command with fallback to 'ifconfig' for compatibility
# Returns: First two octets of 10.x network (e.g., "10.0" or "10.247")
get_network_subnet() {
    local subnet=""
    
    # Try modern ip command first
    if command -v ip >/dev/null 2>&1; then
        subnet=$(ip addr show 2>/dev/null | \
            fgrep -w inet | \
            fgrep -v 127.0.0.1 | \
            fgrep 10. | \
            head -1 | \
            awk '{print $2}' | \
            cut -f1 -d/ | \
            cut -f-2 -d.)
    fi
    
    # Fallback to ifconfig if ip failed or not available
    if [[ -z "$subnet" ]] && command -v ifconfig >/dev/null 2>&1; then
        subnet=$(ifconfig 2>/dev/null | \
            fgrep -w inet | \
            fgrep -v 127.0.0.1 | \
            fgrep 10. | \
            head -1 | \
            awk '{print $2}' | \
            cut -f-2 -d.)
    fi
    
    echo "$subnet"
}

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

# Main function to determine cluster name based on CDC_JOINED_ZONE or network detection
# Sets global CLUSTER variable with detected cluster name
# Uses CDC_JOINED_ZONE environment variable
determine_cluster() {
    local cdc_zone="${CDC_JOINED_ZONE:-UNKNOWN}"
    
    debug_log "Starting cluster determination with CDC_JOINED_ZONE='$cdc_zone'"
    
    if [[ "$cdc_zone" == "UNKNOWN" ]]; then
        debug_log "Using network detection method"
        local subnet
        subnet=$(get_network_subnet)
        debug_log "Detected subnet: '$subnet'"
        
        if [[ -z "$subnet" ]]; then
            CLUSTER="UNKNOWN"
            debug_log "No subnet detected, setting CLUSTER=UNKNOWN"
        elif [[ "$subnet" == "10.0" ]]; then
            CLUSTER="JUNO"
            debug_log "Subnet 10.0 detected, setting CLUSTER=JUNO"
        else
            CLUSTER="UNKNOWN"
            debug_log "Unknown subnet '$subnet', setting CLUSTER=UNKNOWN"
        fi
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
