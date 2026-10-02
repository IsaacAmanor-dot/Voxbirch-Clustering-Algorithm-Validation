#!/bin/bash
#SBATCH --job-name=VoxBirch_threshold
#SBATCH --partition=rn-long-40core
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --time=02:00:00

set -euo pipefail

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

if [[ -z "${SLURM_ARRAY_TASK_ID:-}" ]]; then
    echo "ERROR: This script must be submitted as a SLURM array."
    exit 1
fi

if (( SLURM_ARRAY_TASK_ID >= ${#THRESHOLDS[@]} )); then
    echo "ERROR: Array index is outside the threshold list."
    exit 1
fi

THRESHOLD="${THRESHOLDS[$SLURM_ARRAY_TASK_ID]}"
RUN_DIR="$RESULTS_DIR/threshold_${THRESHOLD}"

echo "VoxBirch threshold experiment"
echo "Job ID:            $SLURM_JOB_ID"
echo "Array task:        $SLURM_ARRAY_TASK_ID"
echo "Node:              $(hostname)"
echo "Project directory: $PROJECT_DIR"
echo "Results directory: $RESULTS_DIR"
echo "Threshold:         $THRESHOLD"
echo "Input molecules:   $N_MOLECULES"
echo "Working directory: $RUN_DIR"
echo "Start time:        $(date)"

if [[ ! -x "$VOXBIRCH_BIN" ]]; then
    echo "ERROR: VoxBirch executable not found:"
    echo "$VOXBIRCH_BIN"
    exit 1
fi

if [[ ! -s "$INPUT_MOL2" ]]; then
    echo "ERROR: Input MOL2 file not found:"
    echo "$INPUT_MOL2"
    exit 1
fi

mkdir -p "$RESULTS_DIR"
mkdir -p "$RUN_DIR"

if [[ -e "$RUN_DIR/birch_tree.mdb" ]] || \
   [[ -e "$RUN_DIR/clustered_mol_ids.txt" ]] || \
   [[ -e "$RUN_DIR/processed_mols" ]] || \
   [[ -e "$RUN_DIR/molecules" ]]; then
    echo "ERROR: Existing VoxBirch results found:"
    echo "$RUN_DIR"
    echo "Existing results will not be overwritten."
    exit 2
fi

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
    > "VoxBirch_${THRESHOLD}.out" 2>&1

EXIT_CODE=$?

set -e

END_EPOCH=$(date +%s.%N)

WALL_SECONDS=$(awk -v start="$START_EPOCH" -v end="$END_EPOCH" \
    'BEGIN {printf "%.6f", end-start}')

echo "$WALL_SECONDS" > wall_time_seconds.txt
echo "$EXIT_CODE" > exit_code.txt
echo "$(hostname)" > node.txt

if [[ "$EXIT_CODE" -eq 0 ]] && [[ -s clustered_mol_ids.txt ]]; then
    touch VOXBIRCH_COMPLETE
    STATUS="COMPLETE"
else
    touch VOXBIRCH_FAILED
    STATUS="FAILED"
fi

echo "Status:            $STATUS"
echo "Threshold:         $THRESHOLD"
echo "Exit code:         $EXIT_CODE"
echo "Wall time:         $WALL_SECONDS seconds"
echo "End time:          $(date)"

exit "$EXIT_CODE"
