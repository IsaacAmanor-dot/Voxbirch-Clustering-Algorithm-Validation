#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/000.config.sh"

printf "%-12s %-12s %-12s %-16s %-14s %-12s\n" \
    "Threshold" "Status" "Clusters" "Internal_Time" "Wall_Time" "Node"

for THRESHOLD in "${THRESHOLDS[@]}"; do

    RUN_DIR="$RESULTS_DIR/threshold_${THRESHOLD}"
    OUT_FILE="$RUN_DIR/VoxBirch_${THRESHOLD}.out"
    WALL_FILE="$RUN_DIR/wall_time_seconds.txt"
    NODE_FILE="$RUN_DIR/node.txt"

    STATUS="NOT_RUN"
    CLUSTERS="NA"
    INTERNAL_TIME="NA"
    WALL_TIME="NA"
    NODE="NA"

    if [[ -f "$RUN_DIR/VOXBIRCH_COMPLETE" ]]; then
        STATUS="COMPLETE"
    elif [[ -f "$RUN_DIR/VOXBIRCH_FAILED" ]]; then
        STATUS="FAILED"
    elif [[ -d "$RUN_DIR" ]]; then
        STATUS="INCOMPLETE"
    fi

    if [[ -s "$OUT_FILE" ]]; then
        CLUSTERS=$(grep -m1 "Total number of clusters:" "$OUT_FILE" \
            | awk '{print $NF}' || true)

        INTERNAL_TIME=$(grep -m1 "Total Elapsed time:" "$OUT_FILE" \
            | sed 's/Total Elapsed time:[[:space:]]*//' || true)

        [[ -n "$CLUSTERS" ]] || CLUSTERS="NA"
        [[ -n "$INTERNAL_TIME" ]] || INTERNAL_TIME="NA"
    fi

    if [[ -s "$WALL_FILE" ]]; then
        WALL_TIME=$(cat "$WALL_FILE")
    fi

    if [[ -s "$NODE_FILE" ]]; then
        NODE=$(cat "$NODE_FILE")
    fi

    printf "%-12s %-12s %-12s %-16s %-14s %-12s\n" \
        "$THRESHOLD" "$STATUS" "$CLUSTERS" "$INTERNAL_TIME" "$WALL_TIME" "$NODE"

done
