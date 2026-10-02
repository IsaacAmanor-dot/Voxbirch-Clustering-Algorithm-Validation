#!/bin/bash
#SBATCH --job-name=VoxBirch_norep
#SBATCH --partition=rn-long-40core
#SBATCH --nodes=1
#SBATCH --ntasks=25
#SBATCH --cpus-per-task=1
#SBATCH --time=02:00:00

set -euo pipefail

# Load experiment configuration
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

# This workflow requires one replicate
if [[ "$N_REPLICATES" -ne 1 ]]; then
    echo "ERROR: This workflow requires N_REPLICATES=1."
    echo "Current value: $N_REPLICATES"
    exit 1
fi

# Check VoxBirch executable
if [[ ! -x "$VOXBIRCH_BIN" ]]; then
    echo "ERROR: VoxBirch executable not found:"
    echo "$VOXBIRCH_BIN"
    exit 1
fi

# Check input library
if [[ ! -s "$INPUT_MOL2" ]]; then
    echo "ERROR: Input MOL2 file not found:"
    echo "$INPUT_MOL2"
    exit 1
fi

N_THRESHOLDS=${#THRESHOLDS[@]}

if (( N_THRESHOLDS > SLURM_NTASKS )); then
    echo "ERROR: Not enough SLURM tasks."
    echo "Thresholds: $N_THRESHOLDS"
    echo "Tasks:      $SLURM_NTASKS"
    exit 1
fi

mkdir -p "$THRESHOLD_RESULTS_DIR"

echo "VoxBirch no-replication threshold experiment"
echo "SLURM job:          $SLURM_JOB_ID"
echo "Node:               $(hostname)"
echo "Molecules:          $N_MOLECULES"
echo "Thresholds:         $N_THRESHOLDS"
echo "Allocated tasks:    $SLURM_NTASKS"
echo "Execution:          concurrent"
echo "Start time:         $(date)"
echo

# Run one threshold
run_threshold() {

    RUN_INDEX="$1"
    THRESHOLD="$2"

    REPLICATE=1
    REPLICATE_PADDED="01"

    RUN_DIR="$THRESHOLD_RESULTS_DIR/threshold_${THRESHOLD}/replicate_${REPLICATE_PADDED}"
    OUT_FILE="VoxBirch_${THRESHOLD}_replicate_${REPLICATE_PADDED}.out"

    mkdir -p "$RUN_DIR"

    if [[ -f "$RUN_DIR/VOXBIRCH_COMPLETE" ]]; then
        echo "SKIP run=$RUN_INDEX threshold=$THRESHOLD already complete"
        return 0
    fi

    if [[ -e "$RUN_DIR/birch_tree.mdb" ]] || \
       [[ -e "$RUN_DIR/clustered_mol_ids.txt" ]] || \
       [[ -e "$RUN_DIR/processed_mols" ]] || \
       [[ -e "$RUN_DIR/molecules" ]] || \
       [[ -e "$RUN_DIR/VOXBIRCH_FAILED" ]]; then

        echo "ERROR run=$RUN_INDEX threshold=$THRESHOLD existing incomplete/failed results"
        return 1
    fi

    echo "START run=$RUN_INDEX threshold=$THRESHOLD node=$(hostname)"

    cd "$RUN_DIR"

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

    echo "$WALL_SECONDS" > wall_time_seconds.txt
    echo "$EXIT_CODE" > exit_code.txt
    echo "$(hostname)" > node.txt
    echo "$THRESHOLD" > threshold.txt
    echo "$REPLICATE" > replicate.txt
    echo "$RUN_INDEX" > run_index.txt

    if [[ "$EXIT_CODE" -eq 0 ]] && [[ -s clustered_mol_ids.txt ]]; then
        rm -f VOXBIRCH_FAILED
        touch VOXBIRCH_COMPLETE
        STATUS="COMPLETE"
    else
        touch VOXBIRCH_FAILED
        STATUS="FAILED"
    fi

    echo "END run=$RUN_INDEX threshold=$THRESHOLD status=$STATUS wall=${WALL_SECONDS}s"

    return "$EXIT_CODE"
}

export -f run_threshold

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

PIDS=()
RUN_INDICES=()

# Launch all thresholds concurrently
for ((RUN_INDEX=0; RUN_INDEX<N_THRESHOLDS; RUN_INDEX++)); do

    THRESHOLD="${THRESHOLDS[$RUN_INDEX]}"

    srun \
        --exclusive \
        --nodes=1 \
        --ntasks=1 \
        --cpus-per-task=1 \
        bash -c "run_threshold '$RUN_INDEX' '$THRESHOLD'" &

    PIDS+=("$!")
    RUN_INDICES+=("$RUN_INDEX")

done

echo
echo "Launched ${#PIDS[@]} threshold calculations concurrently."
echo

FAILED_RUNS=0

# Wait for all thresholds
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

echo
echo "VoxBirch no-replication threshold experiment complete"
echo "Node:               $(hostname)"
echo "Thresholds:         $N_THRESHOLDS"
echo "Failed runs:        $FAILED_RUNS"
echo "End time:           $(date)"

if (( FAILED_RUNS > 0 )); then
    exit 1
fi

exit 0
