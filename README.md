# VoxBirch Clustering Algorithm Validation

This repository provides a general workflow for evaluating the clustering behavior and computational performance of VoxBirch.

The pipeline supports threshold-sensitivity experiments, repeated runtime measurements, clustering validation, and statistical analysis. Experimental parameters are controlled centrally and can be changed for different molecular datasets.

## Workflow

```text
000.config.sh
001.run_thresholds.slurm
002.check_results.sh
003.analyze_results.py
```

### 000.config.sh

Central configuration file for:

- VoxBirch executable
- Input molecular dataset
- Molecular population size
- Clustering thresholds
- Number of replicates
- VoxBirch parameters
- SLURM settings
- Output directories

The remaining scripts read their parameters from this file.

### 001.run_thresholds.slurm

Runs VoxBirch threshold-sensitivity calculations using SLURM.

Each threshold is evaluated over the configured number of replicates. Calculations are distributed across SLURM workers and each run has an independent output directory.

The workflow records:

- VoxBirch output
- Internal runtime
- External wall-clock time
- Compute node
- Threshold and replicate
- Completion or failure status

Submit with:

```bash
sbatch 001.run_thresholds.slurm
```

### 002.check_results.sh

Monitors the experiment and reports the status of each calculation.

```bash
./002.check_results.sh
```

The checker reports:

```text
Threshold
Replicate
Status
Clusters
Internal_Time
Wall_Time
Node
```

It also summarizes overall progress, including completed, incomplete, failed, and remaining calculations.

### 003.analyze_results.py

Validates completed calculations and generates statistical summaries.

```bash
python3 003.analyze_results.py
```

Validation includes:

- Expected molecular population
- Unique molecular assignments
- Duplicate assignments
- Parsed and reported cluster counts

The analysis extracts:

- Number of clusters
- Cluster-size statistics
- Singleton statistics
- Voxelization time
- Clustering time
- Internal runtime
- External wall time
- Processing rate
- Compute node

Replicate-level measurements are retained for statistical analysis.

## Current Threshold Experiment

The current application uses a fixed dataset of 5,282 molecules and evaluates 25 clustering thresholds:

```text
0.10  0.15  0.20  0.25  0.30
0.35  0.40  0.45  0.50  0.525
0.55  0.575 0.60  0.625 0.65
0.675 0.70  0.725 0.75  0.775
0.80  0.825 0.85  0.875 0.90
```

Five replicate executions are performed per threshold:

```text
25 thresholds x 5 replicates = 125 calculations
```

This experiment measures how the clustering threshold affects cluster formation and computational runtime while molecular population size is held constant.

## Output

Results are written under:

```text
zzz.results/
└── threshold_sensitivity/
    ├── threshold_0.10/
    │   ├── replicate_01/
    │   ├── replicate_02/
    │   └── ...
    └── threshold_0.90/
```

The analysis generates:

```text
VoxBirch_threshold_runs.csv
VoxBirch_threshold_summary.csv
```

The run-level file preserves individual replicate measurements, while the summary file contains threshold-level statistics.

## Experimental Analysis

The pipeline is designed to investigate two primary relationships.

### Threshold Sensitivity

At fixed molecular population size:

```text
Runtime = f(threshold)
Clustering behavior = f(threshold)
```

Relevant clustering measurements include the number of clusters, cluster sizes, largest cluster, and singleton fraction.

### Dataset-Size Scaling

The workflow can be extended to vary molecular population size at a fixed threshold:

```text
Runtime = f(N)
```

Empirical computational scaling can then be evaluated using:

```text
T(N) = a N^p
```

where `p` is the empirical scaling exponent.

## Visualization

The generated CSV files provide validated numerical input for downstream statistical analysis and visualization.

VoxBirch results can also be incorporated into `Similarity_Island_plotting` for comparative molecular clustering analysis.

## Repository Scope

This repository contains the VoxBirch validation and benchmarking workflow.

The VoxBirch source code, molecular datasets, generated clustering results, LMDB databases, and other large runtime outputs are maintained separately or excluded from version control.
