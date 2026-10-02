#!/bin/bash

# Project directories
PROJECT_DIR="/gpfs/projects/rizzo/iamanor/Collaborations/Pak/001_VoxBirch_Runtime_Analysis"
RESULTS_DIR="$PROJECT_DIR/zzz.results"
THRESHOLD_RESULTS_DIR="$RESULTS_DIR/threshold_sensitivity"

# VoxBirch executable
VOXBIRCH_BIN="/gpfs/projects/rizzo/iamanor/Collaborations/Pak/000_Program/voxbirch/bin/voxbirch"

# Input molecular library
INPUT_MOL2="/gpfs/projects/rizzo/iamanor/Systems_and_Library_Files/005_Clustering_Dataset/Dock_Scored_Molecules_for_SMI_Clustering_scored.mol2"
N_MOLECULES=5282

# Threshold sensitivity experiment
THRESHOLDS=(0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.525 0.55 0.575 0.60 0.625 0.65 0.675 0.70 0.725 0.75 0.775 0.80 0.825 0.85 0.875 0.90)
N_REPLICATES=5

# VoxBirch parameters
DIMS="20,20,20"
RESOLUTION="1.4142135"
ORIGIN="0.0,0.0,0.0"
MAX_BRANCHES=50
BATCH_SIZE=10000
ATOM_TYPING="explicit-type"
CLUSTER_WRITE_LIMIT=10

# SLURM settings
PARTITION="rn-long-40core"
WALLTIME="02:00:00"
CPUS_PER_TASK=1
MAX_CONCURRENT_TASKS=40
