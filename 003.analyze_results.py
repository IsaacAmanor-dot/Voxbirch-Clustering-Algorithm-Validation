#!/usr/bin/env python3

import csv
import re
import statistics
import subprocess
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
CONFIG_FILE = SCRIPT_DIR / "000.config.sh"


def load_config():
    command = f'''
source "{CONFIG_FILE}"
printf '%s\\n' "$N_MOLECULES"
printf '%s\\n' "$RESULTS_DIR"
printf '%s\\n' "${{THRESHOLDS[*]}}"
'''

    result = subprocess.run(
        ["bash", "-c", command],
        capture_output=True,
        text=True,
        check=True,
    )

    lines = result.stdout.strip().splitlines()

    if len(lines) != 3:
        raise RuntimeError("Could not read 000.config.sh")

    expected_molecules = int(lines[0])
    results_dir = Path(lines[1])
    thresholds = lines[2].split()

    return expected_molecules, results_dir, thresholds


def parse_cluster_file(path):
    clusters = {}
    current_cluster = None

    with path.open("r") as handle:
        for line in handle:
            line = line.strip()

            if not line:
                continue

            if line.startswith("index:"):
                current_cluster = int(line.split(":", 1)[1].strip())

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

                match = re.match(r"mol\s+(\d+):\s+(.+)", line)

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


def analyze_threshold(
    threshold,
    expected_molecules,
    results_dir,
):
    run_dir = results_dir / f"threshold_{threshold}"
    cluster_file = run_dir / "clustered_mol_ids.txt"
    output_file = run_dir / f"VoxBirch_{threshold}.out"
    wall_file = run_dir / "wall_time_seconds.txt"
    node_file = run_dir / "node.txt"

    if not cluster_file.exists():
        return {
            "threshold": threshold,
            "status": "NOT_RUN",
        }

    try:
        clusters = parse_cluster_file(cluster_file)
    except Exception as error:
        return {
            "threshold": threshold,
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
    duplicate_assignments = total_molecules - unique_molecules

    if cluster_sizes:
        largest_cluster = max(cluster_sizes)
        smallest_cluster = min(cluster_sizes)
        mean_cluster_size = statistics.mean(cluster_sizes)
        singleton_clusters = sum(
            size == 1 for size in cluster_sizes
        )
        singleton_fraction = singleton_clusters / total_clusters
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
        "threshold": threshold,
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


def write_csv(results, output_csv):
    fieldnames = [
        "threshold",
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

    with output_csv.open("w", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=fieldnames,
            extrasaction="ignore",
        )

        writer.writeheader()
        writer.writerows(results)


def print_summary(results, output_csv):
    print()
    print("VoxBirch threshold analysis")
    print()

    print(
        f"{'Threshold':<11}"
        f"{'Status':<12}"
        f"{'Molecules':>11}"
        f"{'Clusters':>10}"
        f"{'Largest':>10}"
        f"{'Mean':>10}"
        f"{'Singletons':>12}"
    )

    for result in results:
        threshold = result["threshold"]
        status = result["status"]

        if status == "NOT_RUN":
            print(
                f"{threshold:<11}"
                f"{status:<12}"
            )
            continue

        print(
            f"{threshold:<11}"
            f"{status:<12}"
            f"{result.get('number_of_molecules', 0):>11}"
            f"{result.get('number_of_clusters', 0):>10}"
            f"{result.get('largest_cluster', 0):>10}"
            f"{result.get('mean_cluster_size', 0):>10.2f}"
            f"{result.get('singleton_clusters', 0):>12}"
        )

    print()
    print(f"Analysis CSV: {output_csv}")


def main():
    expected_molecules, results_dir, thresholds = load_config()

    results_dir.mkdir(parents=True, exist_ok=True)

    output_csv = (
        results_dir
        / "VoxBirch_threshold_analysis.csv"
    )

    results = [
        analyze_threshold(
            threshold,
            expected_molecules,
            results_dir,
        )
        for threshold in thresholds
    ]

    write_csv(results, output_csv)
    print_summary(results, output_csv)


if __name__ == "__main__":
    main()
