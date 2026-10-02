#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/000.config.sh"

TOTAL_RUNS=$((${#THRESHOLDS[@]} * N_REPLICATES))

COMPLETE_COUNT=0
INCOMPLETE_COUNT=0
FAILED_COUNT=0
NOT_RUN_COUNT=0
COMPLETE_THRESHOLDS=0

printf "%-10s %-10s %-12s %-10s %-16s %-14s %-12s\n" \
    "Threshold" "Replicate" "Status" "Clusters" \
    "Internal_Time" "Wall_Time" "Node"

for THRESHOLD in "${THRESHOLDS[@]}"; do

    THRESHOLD_COMPLETE=0

    for ((REPLICATE=1; REPLICATE<=N_REPLICATES; REPLICATE++)); do

        REPLICATE_PADDED=$(printf "%02d" "$REPLICATE")

        RUN_DIR="$THRESHOLD_RESULTS_DIR/threshold_${THRESHOLD}/replicate_${REPLICATE_PADDED}"

        OUT_FILE="$RUN_DIR/VoxBirch_${THRESHOLD}_replicate_${REPLICATE_PADDED}.out"
        WALL_FILE="$RUN_DIR/wall_time_seconds.txt"
        NODE_FILE="$RUN_DIR/node.txt"

        STATUS="NOT_RUN"
        CLUSTERS="NA"
        INTERNAL_TIME="NA"
        WALL_TIME="NA"
        NODE="NA"

        if [[ -f "$RUN_DIR/VOXBIRCH_COMPLETE" ]]; then
            STATUS="COMPLETE"
            ((COMPLETE_COUNT+=1))
            ((THRESHOLD_COMPLETE+=1))

        elif [[ -f "$RUN_DIR/VOXBIRCH_FAILED" ]]; then
            STATUS="FAILED"
            ((FAILED_COUNT+=1))

        elif [[ -d "$RUN_DIR" ]]; then
            STATUS="INCOMPLETE"
            ((INCOMPLETE_COUNT+=1))

        else
            ((NOT_RUN_COUNT+=1))
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

        printf "%-10s %-10s %-12s %-10s %-16s %-14s %-12s\n" \
            "$THRESHOLD" \
            "$REPLICATE_PADDED" \
            "$STATUS" \
            "$CLUSTERS" \
            "$INTERNAL_TIME" \
            "$WALL_TIME" \
            "$NODE"

    done

    if (( THRESHOLD_COMPLETE == N_REPLICATES )); then
        ((COMPLETE_THRESHOLDS+=1))
    fi

done

TOTAL_THRESHOLDS=${#THRESHOLDS[@]}

RUN_PROGRESS=$(awk -v c="$COMPLETE_COUNT" -v t="$TOTAL_RUNS" \
    'BEGIN {printf "%.2f", 100*c/t}')

THRESHOLD_PROGRESS=$(awk -v c="$COMPLETE_THRESHOLDS" -v t="$TOTAL_THRESHOLDS" \
    'BEGIN {printf "%.2f", 100*c/t}')

REMAINING_COUNT=$((TOTAL_RUNS - COMPLETE_COUNT))

echo
echo "VoxBirch Threshold Sensitivity Progress"
echo
printf "%-28s %d\n" "Total calculations:" "$TOTAL_RUNS"
printf "%-28s %d\n" "Complete:" "$COMPLETE_COUNT"
printf "%-28s %d\n" "Incomplete:" "$INCOMPLETE_COUNT"
printf "%-28s %d\n" "Not started:" "$NOT_RUN_COUNT"
printf "%-28s %d\n" "Failed:" "$FAILED_COUNT"
printf "%-28s %d\n" "Remaining:" "$REMAINING_COUNT"
printf "%-28s %s%%\n" "Run progress:" "$RUN_PROGRESS"
echo
printf "%-28s %d / %d\n" \
    "Thresholds complete:" "$COMPLETE_THRESHOLDS" "$TOTAL_THRESHOLDS"
printf "%-28s %s%%\n" \
    "Threshold progress:" "$THRESHOLD_PROGRESS"
printf "%-28s %d\n" \
    "Replicates per threshold:" "$N_REPLICATES"
