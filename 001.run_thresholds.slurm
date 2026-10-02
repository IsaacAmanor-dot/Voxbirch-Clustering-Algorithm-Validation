#!/bin/bash
#SBATCH --job-name=VoxBirch_threshold
#SBATCH --partition=rn-long-40core
#SBATCH --nodes=1
#SBATCH --ntasks=40
#SBATCH --cpus-per-task=1
#SBATCH --time=02:00:00
#SBATCH --array=0-2

set -euo pipefail

# Load the experiment configuration
if [[ -z "${SLURM_SUBMIT_DIR:-}" ]]; then
    echo "ERROR: SLURM_SUBMIT_DIR is not defined."
    exit 1
fi

CONFIG_FILE="$SLURM_SUBMIT_DIR/000.config.sh"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: Configuration file not found:"
    echo "$CONFIG_FILE"
    exit 1
fi

source "$CONFIG_FILE"

# Confirm that this is running as a SLURM array
if [[ -z "${SLURM_ARRAY_TASK_ID:-}" ]]; then
    echo "ERROR: This script must be submitted as a SLURM array."
    exit 1
fi

# Calculate the total number of VoxBirch runs
N_THRESHOLDS=${#THRESHOLDS[@]}
TOTAL_RUNS=$((N_THRESHOLDS * N_REPLICATES))

# Three array workers share all calculations
N_WORKERS=3
WORKER_ID="$SLURM_ARRAY_TASK_ID"

if (( WORKER_ID < 0 || WORKER_ID >= N_WORKERS )); then
    echo "ERROR: Invalid worker ID: $WORKER_ID"
    exit 1
fi

# Check the VoxBirch executable
if [[ ! -x "$VOXBIRCH_BIN" ]]; then
    echo "ERROR: VoxBirch executable not found:"
    echo "$VOXBIRCH_BIN"
    exit 1
fi

# Check the input molecular library
if [[ ! -s "$INPUT_MOL2" ]]; then
    echo "ERROR: Input MOL2 file not found:"
    echo "$INPUT_MOL2"
    exit 1
fi

echo "VoxBirch threshold sensitivity experiment"
echo "SLURM job:          $SLURM_JOB_ID"
echo "Worker:             $WORKER_ID"
echo "Node:               $(hostname)"
echo "Allocated tasks:    $SLURM_NTASKS"
echo "Total runs:         $TOTAL_RUNS"
echo "Workers:            $N_WORKERS"
echo "Start time:         $(date)"

# Run one threshold-replicate calculation
run_voxbirch() {

    RUN_INDEX="$1"

    # Convert the run index into threshold and replicate
    THRESHOLD_INDEX=$((RUN_INDEX / N_REPLICATES))
    REPLICATE=$((RUN_INDEX % N_REPLICATES + 1))

    THRESHOLD="${THRESHOLDS[$THRESHOLD_INDEX]}"
    REPLICATE_PADDED=$(printf "%02d" "$REPLICATE")

    # Each calculation has its own directory
    RUN_DIR="$THRESHOLD_RESULTS_DIR/threshold_${THRESHOLD}/replicate_${REPLICATE_PADDED}"
    OUT_FILE="VoxBirch_${THRESHOLD}_replicate_${REPLICATE_PADDED}.out"

    mkdir -p "$RUN_DIR"

    # Do not repeat completed calculations
    if [[ -f "$RUN_DIR/VOXBIRCH_COMPLETE" ]]; then
        echo "SKIP run $RUN_INDEX: already complete"
        return 0
    fi

    # Protect existing incomplete or failed results
    if [[ -e "$RUN_DIR/birch_tree.mdb" ]] || \
       [[ -e "$RUN_DIR/clustered_mol_ids.txt" ]] || \
       [[ -e "$RUN_DIR/processed_mols" ]] || \
       [[ -e "$RUN_DIR/molecules" ]] || \
       [[ -e "$RUN_DIR/VOXBIRCH_FAILED" ]]; then

        echo "SKIP run $RUN_INDEX: existing incomplete/failed results"
        return 0
    fi

    echo "START run=$RUN_INDEX threshold=$THRESHOLD replicate=$REPLICATE node=$(hostname)"

    cd "$RUN_DIR"

    # Record the external wall-clock time
    START_EPOCH=$(date +%s.%N)

    set +e

    "$VOXBIRCH_BIN" \
        -p "$INPUT_MOL2" \
        -d "$DIMS" \
        -r "$RESOLUTION" \
        -o "$ORIGIN" \
        -t "$THRESHOLD" \
        -m "$MAX_BRANCHES" \
        -c "$CLUSTER_WRITE_LIMIT" \
        --batch-size "$BATCH_SIZE" \
        --atom-typing "$ATOM_TYPING" \
        > "$OUT_FILE" 2>&1

    EXIT_CODE=$?

    set -e

    END_EPOCH=$(date +%s.%N)

    WALL_SECONDS=$(awk -v start="$START_EPOCH" -v end="$END_EPOCH" \
        'BEGIN {printf "%.6f", end-start}')

    # Save metadata for this calculation
    echo "$WALL_SECONDS" > wall_time_seconds.txt
    echo "$EXIT_CODE" > exit_code.txt
    echo "$(hostname)" > node.txt
    echo "$THRESHOLD" > threshold.txt
    echo "$REPLICATE" > replicate.txt
    echo "$RUN_INDEX" > run_index.txt
    echo "$SLURM_ARRAY_TASK_ID" > array_task_id.txt

    # Mark the calculation as complete or failed
    if [[ "$EXIT_CODE" -eq 0 ]] && [[ -s clustered_mol_ids.txt ]]; then
        rm -f VOXBIRCH_FAILED
        touch VOXBIRCH_COMPLETE
        STATUS="COMPLETE"
    else
        touch VOXBIRCH_FAILED
        STATUS="FAILED"
    fi

    echo "END run=$RUN_INDEX threshold=$THRESHOLD replicate=$REPLICATE status=$STATUS wall=${WALL_SECONDS}s"

    cd "$SLURM_SUBMIT_DIR"

    return "$EXIT_CODE"
}

# Export variables needed by each srun process
export VOXBIRCH_BIN
export INPUT_MOL2
export DIMS
export RESOLUTION
export ORIGIN
export MAX_BRANCHES
export CLUSTER_WRITE_LIMIT
export BATCH_SIZE
export ATOM_TYPING
export THRESHOLD_RESULTS_DIR
export N_REPLICATES
export SLURM_SUBMIT_DIR
export SLURM_ARRAY_TASK_ID

PIDS=()
RUN_INDICES=()

# Distribute calculations across the three workers
# Worker 0: 0, 3, 6, 9, ...
# Worker 1: 1, 4, 7, 10, ...
# Worker 2: 2, 5, 8, 11, ...
for ((RUN_INDEX=WORKER_ID; RUN_INDEX<TOTAL_RUNS; RUN_INDEX+=N_WORKERS)); do

    # Give each VoxBirch calculation one task/core
    srun \
        --exclusive \
        --nodes=1 \
        --ntasks=1 \
        --cpus-per-task=1 \
        bash -c "$(declare -f run_voxbirch); \
                  THRESHOLDS=(${THRESHOLDS[*]}); \
                  run_voxbirch '$RUN_INDEX'" &

    # Save the process ID so we can wait for it later
    PIDS+=("$!")
    RUN_INDICES+=("$RUN_INDEX")

done

echo "Worker $WORKER_ID launched ${#PIDS[@]} calculations."

# Wait until every calculation assigned to this worker finishes
FAILED_RUNS=0

for i in "${!PIDS[@]}"; do

    PID="${PIDS[$i]}"
    RUN_INDEX="${RUN_INDICES[$i]}"

    if wait "$PID"; then
        :
    else
        echo "ERROR: run $RUN_INDEX failed."
        FAILED_RUNS=$((FAILED_RUNS + 1))
    fi

done

# Report the final worker status
echo "Worker complete"
echo "Worker:             $WORKER_ID"
echo "Node:               $(hostname)"
echo "Calculations:       ${#PIDS[@]}"
echo "Failed runs:        $FAILED_RUNS"
echo "End time:           $(date)"

if (( FAILED_RUNS > 0 )); then
    exit 1
fi

exit 0
