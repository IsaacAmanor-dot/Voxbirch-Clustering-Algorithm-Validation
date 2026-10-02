#!/usr/bin/env python3

import csv
import math
import re
import statistics
import subprocess

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from collections import defaultdict
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
CONFIG_FILE = SCRIPT_DIR / "000.config.sh"


def load_config():
    command = f'''
source "{CONFIG_FILE}"
printf '%s\\n' "$N_MOLECULES"
printf '%s\\n' "$THRESHOLD_RESULTS_DIR"
printf '%s\\n' "$N_REPLICATES"
printf '%s\\n' "${{THRESHOLDS[*]}}"
'''

    result = subprocess.run(
        ["bash", "-c", command],
        capture_output=True,
        text=True,
        check=True,
    )

    lines = result.stdout.strip().splitlines()

    if len(lines) != 4:
        raise RuntimeError("Could not read 000.config.sh")

    expected_molecules = int(lines[0])
    results_dir = Path(lines[1])
    n_replicates = int(lines[2])
    thresholds = lines[3].split()

    return (
        expected_molecules,
        results_dir,
        n_replicates,
        thresholds,
    )


def parse_cluster_file(path):
    clusters = {}
    current_cluster = None

    with path.open("r") as handle:
        for line in handle:
            line = line.strip()

            if not line:
                continue

            if line.startswith("index:"):
                current_cluster = int(
                    line.split(":", 1)[1].strip()
                )

                if current_cluster in clusters:
                    raise ValueError(
                        f"Duplicate cluster index {current_cluster}"
                    )

                clusters[current_cluster] = []

            elif line.startswith("mol "):
                if current_cluster is None:
                    raise ValueError(
                        "Molecule encountered before cluster index"
                    )

                match = re.match(
                    r"mol\s+(\d+):\s+(.+)",
                    line,
                )

                if not match:
                    raise ValueError(
                        f"Could not parse molecule line: {line}"
                    )

                molecule_index = int(match.group(1))
                molecule_name = match.group(2).strip()

                clusters[current_cluster].append(
                    (molecule_index, molecule_name)
                )

    return clusters


def time_to_seconds(match):
    hours = int(match.group(1))
    minutes = int(match.group(2))
    seconds = int(match.group(3))
    milliseconds = int(match.group(4))

    return (
        hours * 3600
        + minutes * 60
        + seconds
        + milliseconds / 1000.0
    )


def parse_voxbirch_output(path):
    metrics = {
        "reported_clusters": None,
        "voxelization_seconds": None,
        "clustering_seconds": None,
        "internal_total_seconds": None,
        "molecules_per_second": None,
        "seconds_per_molecule": None,
    }

    if not path.exists():
        return metrics

    text = path.read_text(errors="replace")

    match = re.search(
        r"Total number of clusters:\s*(\d+)",
        text,
    )
    if match:
        metrics["reported_clusters"] = int(match.group(1))

    match = re.search(
        r"Elapsed time for Voxelization:\s*"
        r"(\d+)h\s*(\d+)m\s*(\d+)s\s*(\d+)ms",
        text,
    )
    if match:
        metrics["voxelization_seconds"] = time_to_seconds(match)

    match = re.search(
        r"Elapsed time for Clustering:\s*"
        r"(\d+)h\s*(\d+)m\s*(\d+)s\s*(\d+)ms",
        text,
    )
    if match:
        metrics["clustering_seconds"] = time_to_seconds(match)

    match = re.search(
        r"Total Elapsed time:\s*"
        r"(\d+)h\s*(\d+)m\s*(\d+)s\s*(\d+)ms",
        text,
    )
    if match:
        metrics["internal_total_seconds"] = time_to_seconds(match)

    match = re.search(
        r"Number of molecules processed per sec during Clustering:\s*"
        r"([0-9.eE+-]+)",
        text,
    )
    if match:
        metrics["molecules_per_second"] = float(match.group(1))

    match = re.search(
        r"Number of sec per molecule processed during Clustering:\s*"
        r"([0-9.eE+-]+)",
        text,
    )
    if match:
        metrics["seconds_per_molecule"] = float(match.group(1))

    return metrics


def read_float(path):
    if not path.exists():
        return None

    try:
        return float(path.read_text().strip())
    except ValueError:
        return None


def read_text(path):
    if not path.exists():
        return None

    value = path.read_text().strip()

    return value if value else None


def analyze_run(
    threshold,
    replicate,
    expected_molecules,
    results_dir,
):
    replicate_padded = f"{replicate:02d}"

    run_dir = (
        results_dir
        / f"threshold_{threshold}"
        / f"replicate_{replicate_padded}"
    )

    cluster_file = run_dir / "clustered_mol_ids.txt"

    output_file = (
        run_dir
        / f"VoxBirch_{threshold}_replicate_{replicate_padded}.out"
    )

    wall_file = run_dir / "wall_time_seconds.txt"
    node_file = run_dir / "node.txt"

    base_result = {
        "threshold": threshold,
        "replicate": replicate,
    }

    if not run_dir.exists():
        return {
            **base_result,
            "status": "NOT_RUN",
        }

    if (run_dir / "VOXBIRCH_FAILED").exists():
        return {
            **base_result,
            "status": "FAILED",
        }

    if not cluster_file.exists():
        return {
            **base_result,
            "status": "INCOMPLETE",
        }

    try:
        clusters = parse_cluster_file(cluster_file)
    except Exception as error:
        return {
            **base_result,
            "status": f"PARSE_ERROR: {error}",
        }

    cluster_sizes = [
        len(members)
        for members in clusters.values()
    ]

    molecule_indices = [
        molecule_index
        for members in clusters.values()
        for molecule_index, _ in members
    ]

    total_clusters = len(cluster_sizes)
    total_molecules = sum(cluster_sizes)
    unique_molecules = len(set(molecule_indices))
    duplicate_assignments = (
        total_molecules - unique_molecules
    )

    if cluster_sizes:
        largest_cluster = max(cluster_sizes)
        smallest_cluster = min(cluster_sizes)
        mean_cluster_size = statistics.mean(cluster_sizes)

        singleton_clusters = sum(
            size == 1
            for size in cluster_sizes
        )

        singleton_fraction = (
            singleton_clusters / total_clusters
        )
    else:
        largest_cluster = 0
        smallest_cluster = 0
        mean_cluster_size = 0.0
        singleton_clusters = 0
        singleton_fraction = 0.0

    output_metrics = parse_voxbirch_output(output_file)
    wall_time = read_float(wall_file)
    node = read_text(node_file)

    validation_errors = []

    if total_molecules != expected_molecules:
        validation_errors.append(
            f"molecule_count={total_molecules}"
        )

    if unique_molecules != expected_molecules:
        validation_errors.append(
            f"unique_molecules={unique_molecules}"
        )

    if duplicate_assignments != 0:
        validation_errors.append(
            f"duplicate_assignments={duplicate_assignments}"
        )

    reported_clusters = output_metrics["reported_clusters"]

    if (
        reported_clusters is not None
        and reported_clusters != total_clusters
    ):
        validation_errors.append(
            f"cluster_count={total_clusters},"
            f"reported={reported_clusters}"
        )

    status = (
        "VALID"
        if not validation_errors
        else "INVALID: " + "; ".join(validation_errors)
    )

    return {
        **base_result,
        "status": status,
        "number_of_molecules": total_molecules,
        "unique_molecules": unique_molecules,
        "number_of_clusters": total_clusters,
        "reported_clusters": reported_clusters,
        "largest_cluster": largest_cluster,
        "smallest_cluster": smallest_cluster,
        "mean_cluster_size": mean_cluster_size,
        "singleton_clusters": singleton_clusters,
        "singleton_fraction": singleton_fraction,
        "duplicate_assignments": duplicate_assignments,
        "voxelization_seconds":
            output_metrics["voxelization_seconds"],
        "clustering_seconds":
            output_metrics["clustering_seconds"],
        "internal_total_seconds":
            output_metrics["internal_total_seconds"],
        "external_wall_seconds": wall_time,
        "molecules_per_second":
            output_metrics["molecules_per_second"],
        "seconds_per_molecule":
            output_metrics["seconds_per_molecule"],
        "node": node,
    }


def mean_or_none(values):
    values = [
        value
        for value in values
        if value is not None
    ]

    if not values:
        return None

    return statistics.mean(values)


def sd_or_none(values):
    values = [
        value
        for value in values
        if value is not None
    ]

    if len(values) < 2:
        return None

    return statistics.stdev(values)


def cv_percent(mean_value, sd_value):
    if mean_value in (None, 0) or sd_value is None:
        return None

    return 100.0 * sd_value / mean_value


def ci95_half_width(values):
    values = [
        value
        for value in values
        if value is not None
    ]

    n = len(values)

    if n < 2:
        return None

    sd = statistics.stdev(values)

    t_critical = {
        2: 12.706,
        3: 4.303,
        4: 3.182,
        5: 2.776,
    }.get(n, 1.96)

    return t_critical * sd / math.sqrt(n)


def summarize_thresholds(results, thresholds):
    grouped = defaultdict(list)

    for result in results:
        if result.get("status") == "VALID":
            grouped[result["threshold"]].append(result)

    summaries = []

    for threshold in thresholds:
        rows = grouped.get(threshold, [])

        clustering_times = [
            row.get("clustering_seconds")
            for row in rows
        ]

        internal_times = [
            row.get("internal_total_seconds")
            for row in rows
        ]

        wall_times = [
            row.get("external_wall_seconds")
            for row in rows
        ]

        voxelization_times = [
            row.get("voxelization_seconds")
            for row in rows
        ]

        cluster_counts = [
            row.get("number_of_clusters")
            for row in rows
        ]

        largest_clusters = [
            row.get("largest_cluster")
            for row in rows
        ]

        mean_cluster_sizes = [
            row.get("mean_cluster_size")
            for row in rows
        ]

        singleton_fractions = [
            row.get("singleton_fraction")
            for row in rows
        ]

        clustering_mean = mean_or_none(clustering_times)
        clustering_sd = sd_or_none(clustering_times)

        internal_mean = mean_or_none(internal_times)
        internal_sd = sd_or_none(internal_times)

        wall_mean = mean_or_none(wall_times)
        wall_sd = sd_or_none(wall_times)

        summaries.append({
            "threshold": threshold,
            "valid_replicates": len(rows),

            "mean_number_of_clusters":
                mean_or_none(cluster_counts),

            "mean_largest_cluster":
                mean_or_none(largest_clusters),

            "mean_cluster_size":
                mean_or_none(mean_cluster_sizes),

            "mean_singleton_fraction":
                mean_or_none(singleton_fractions),

            "mean_voxelization_seconds":
                mean_or_none(voxelization_times),

            "mean_clustering_seconds":
                clustering_mean,

            "sd_clustering_seconds":
                clustering_sd,

            "cv_clustering_percent":
                cv_percent(
                    clustering_mean,
                    clustering_sd,
                ),

            "ci95_clustering_half_width":
                ci95_half_width(clustering_times),

            "mean_internal_total_seconds":
                internal_mean,

            "sd_internal_total_seconds":
                internal_sd,

            "cv_internal_total_percent":
                cv_percent(
                    internal_mean,
                    internal_sd,
                ),

            "ci95_internal_total_half_width":
                ci95_half_width(internal_times),

            "mean_external_wall_seconds":
                wall_mean,

            "sd_external_wall_seconds":
                wall_sd,

            "cv_external_wall_percent":
                cv_percent(
                    wall_mean,
                    wall_sd,
                ),

            "ci95_external_wall_half_width":
                ci95_half_width(wall_times),
        })

    return summaries


def make_plots(results, plot_dir):
    plot_dir.mkdir(parents=True, exist_ok=True)

    grouped = defaultdict(list)

    for result in results:
        if result.get("status") == "VALID":
            grouped[float(result["threshold"])].append(result)

    cutoffs = sorted(grouped)

    wall_means = []
    wall_sds = []
    mean_cluster_sizes = []
    singleton_counts = []

    for cutoff in cutoffs:
        rows = grouped[cutoff]

        wall_times = [
            row["external_wall_seconds"]
            for row in rows
            if row.get("external_wall_seconds") is not None
        ]

        cluster_sizes = [
            row["mean_cluster_size"]
            for row in rows
        ]

        singletons = [
            row["singleton_clusters"]
            for row in rows
        ]

        wall_means.append(statistics.mean(wall_times))

        if len(wall_times) > 1:
            wall_sds.append(statistics.stdev(wall_times))
        else:
            wall_sds.append(0.0)

        mean_cluster_sizes.append(
            statistics.mean(cluster_sizes)
        )

        singleton_counts.append(
            statistics.mean(singletons)
        )

    fig, ax = plt.subplots(figsize=(7, 5))

    ax.errorbar(
        cutoffs,
        wall_means,
        yerr=wall_sds,
        marker="o",
        capsize=3,
    )

    ax.set_xlabel("VoxBirch Cutoff")
    ax.set_ylabel("Wall Time (s)")
    ax.set_title("VoxBirch Cutoff vs Wall Time")
    ax.grid(alpha=0.25)

    fig.tight_layout()
    fig.savefig(
        plot_dir / "VoxBirch_cutoff_vs_walltime.png",
        dpi=300,
    )
    plt.close(fig)

    fig, ax = plt.subplots(figsize=(7, 5))

    ax.plot(
        cutoffs,
        mean_cluster_sizes,
        marker="o",
    )

    ax.set_xlabel("VoxBirch Cutoff")
    ax.set_ylabel("Mean Cluster Size")
    ax.set_title("VoxBirch Cutoff vs Mean Cluster Size")
    ax.grid(alpha=0.25)

    fig.tight_layout()
    fig.savefig(
        plot_dir / "VoxBirch_cutoff_vs_mean_cluster_size.png",
        dpi=300,
    )
    plt.close(fig)

    fig, ax = plt.subplots(figsize=(7, 5))

    ax.plot(
        cutoffs,
        singleton_counts,
        marker="o",
    )

    ax.set_xlabel("VoxBirch Cutoff")
    ax.set_ylabel("Number of Singleton Clusters")
    ax.set_title("VoxBirch Cutoff vs Singletons")
    ax.grid(alpha=0.25)

    fig.tight_layout()
    fig.savefig(
        plot_dir / "VoxBirch_cutoff_vs_singletons.png",
        dpi=300,
    )
    plt.close(fig)

    print()
    print(f"Analysis plots: {plot_dir}")


def write_csv(rows, path, fieldnames):
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=fieldnames,
            extrasaction="ignore",
        )

        writer.writeheader()
        writer.writerows(rows)


def print_run_summary(results):
    print()
    print("VoxBirch threshold sensitivity analysis")
    print()

    print(
        f"{'Threshold':<11}"
        f"{'Rep':<6}"
        f"{'Status':<12}"
        f"{'Clusters':>10}"
        f"{'Largest':>10}"
        f"{'Mean':>10}"
        f"{'Singletons':>12}"
        f"{'Cluster_s':>12}"
        f"{'Total_s':>12}"
        f"{'Wall_s':>12}"
    )

    for result in results:
        threshold = result["threshold"]
        replicate = result["replicate"]
        status = result["status"]

        if status != "VALID":
            print(
                f"{threshold:<11}"
                f"{replicate:<6}"
                f"{status:<12}"
            )
            continue

        print(
            f"{threshold:<11}"
            f"{replicate:<6}"
            f"{status:<12}"
            f"{result['number_of_clusters']:>10}"
            f"{result['largest_cluster']:>10}"
            f"{result['mean_cluster_size']:>10.2f}"
            f"{result['singleton_clusters']:>12}"
            f"{result['clustering_seconds']:>12.3f}"
            f"{result['internal_total_seconds']:>12.3f}"
            f"{result['external_wall_seconds']:>12.3f}"
        )


def main():
    (
        expected_molecules,
        results_dir,
        n_replicates,
        thresholds,
    ) = load_config()

    results_dir.mkdir(parents=True, exist_ok=True)

    run_results = []

    for threshold in thresholds:
        for replicate in range(1, n_replicates + 1):
            run_results.append(
                analyze_run(
                    threshold,
                    replicate,
                    expected_molecules,
                    results_dir,
                )
            )

    run_csv = (
        results_dir
        / "VoxBirch_threshold_runs.csv"
    )

    summary_csv = (
        results_dir
        / "VoxBirch_threshold_summary.csv"
    )

    run_fields = [
        "threshold",
        "replicate",
        "status",
        "number_of_molecules",
        "unique_molecules",
        "number_of_clusters",
        "reported_clusters",
        "largest_cluster",
        "smallest_cluster",
        "mean_cluster_size",
        "singleton_clusters",
        "singleton_fraction",
        "duplicate_assignments",
        "voxelization_seconds",
        "clustering_seconds",
        "internal_total_seconds",
        "external_wall_seconds",
        "molecules_per_second",
        "seconds_per_molecule",
        "node",
    ]

    summary_fields = [
        "threshold",
        "valid_replicates",
        "mean_number_of_clusters",
        "mean_largest_cluster",
        "mean_cluster_size",
        "mean_singleton_fraction",
        "mean_voxelization_seconds",
        "mean_clustering_seconds",
        "sd_clustering_seconds",
        "cv_clustering_percent",
        "ci95_clustering_half_width",
        "mean_internal_total_seconds",
        "sd_internal_total_seconds",
        "cv_internal_total_percent",
        "ci95_internal_total_half_width",
        "mean_external_wall_seconds",
        "sd_external_wall_seconds",
        "cv_external_wall_percent",
        "ci95_external_wall_half_width",
    ]

    write_csv(
        run_results,
        run_csv,
        run_fields,
    )

    summary_results = summarize_thresholds(
        run_results,
        thresholds,
    )

    write_csv(
        summary_results,
        summary_csv,
        summary_fields,
    )

    plot_dir = SCRIPT_DIR / "zzz.analysis.plots"
    make_plots(run_results, plot_dir)

    print_run_summary(run_results)

    print()
    print(f"Run-level CSV: {run_csv}")
    print(f"Threshold summary CSV: {summary_csv}")


if __name__ == "__main__":
    main()
