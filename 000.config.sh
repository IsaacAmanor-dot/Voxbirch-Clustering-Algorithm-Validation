#!/bin/bash

# Project directories
PROJECT_DIR="/gpfs/projects/rizzo/iamanor/Collaborations/Pak/001_VoxBirch_Runtime_Analysis"
RESULTS_DIR="$PROJECT_DIR/zzz.results"

# VoxBirch executable
VOXBIRCH_BIN="/gpfs/projects/rizzo/iamanor/Collaborations/Pak/000_Program/voxbirch/bin/voxbirch"

# Input molecular library
INPUT_MOL2="/gpfs/projects/rizzo/iamanor/Systems_and_Library_Files/005_Clustering_Dataset/Dock_Scored_Molecules_for_SMI_Clustering_scored.mol2"
N_MOLECULES=5282

# Threshold experiment
THRESHOLDS=(0.10 0.20 0.30 0.40 0.50 0.60 0.65 0.70 0.80 0.90)

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
