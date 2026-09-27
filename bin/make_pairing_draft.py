#!/usr/bin/env python3
"""Draft a TEMPO pairing file from a TEMPO mapping file.

Each SAMPLE ID is parsed with two regexes: one whose first capture group
gives the patient ID and one whose first capture group gives the sample
type. Within each patient every tumor is paired with every normal.

Example:
    ./make_pairing_draft.py mapping_bam_tempo.tsv \\
        '^(\\S+_\\S+)_' '_([TN])\\d+$' -o pairing_bam_tempo.tsv
"""

import argparse
import csv
import re
import sys
from collections import defaultdict


def parse_args() -> argparse.Namespace:
    """Parse command line arguments.

    Returns:
        Parsed arguments.
    """
    parser = argparse.ArgumentParser(
        description="Draft a TEMPO pairing file from a TEMPO mapping file."
    )
    parser.add_argument("mapping", help="TEMPO mapping file (TSV with SAMPLE column)")
    parser.add_argument("patient_regex", help="Regex; group 1 is the patient ID")
    parser.add_argument("type_regex", help="Regex; group 1 is the sample type")
    parser.add_argument(
        "-o", "--output", help="Output pairing file (default: stdout)"
    )
    parser.add_argument(
        "--tumor", default="T", help="Sample type value for tumors (default: T)"
    )
    parser.add_argument(
        "--normal", default="N", help="Sample type value for normals (default: N)"
    )
    parser.add_argument(
        "-u",
        "--unmatched",
        default="_UNMATCHED",
        help="NORMAL_ID used for tumors with no normal (default: _UNMATCHED)",
    )
    return parser.parse_args()


def warn(msg: str) -> None:
    """Print a warning to stderr.

    Args:
        msg: Warning text.
    """
    print(f"WARNING: {msg}", file=sys.stderr)


def extract(pattern: re.Pattern, sample: str) -> str | None:
    """Return capture group 1 of the first match of pattern in sample.

    Args:
        pattern: Compiled regex with at least one capture group.
        sample: Sample ID.

    Returns:
        The captured string, or None if there is no match.
    """
    m = pattern.search(sample)
    return m.group(1) if m else None


def read_samples(path: str) -> list[str]:
    """Read unique SAMPLE IDs from a mapping file, in file order.

    Args:
        path: Path to the TEMPO mapping file.

    Returns:
        Unique sample IDs.

    Raises:
        SystemExit: If the file has no SAMPLE column.
    """
    with open(path, newline="") as fh:
        reader = csv.DictReader(fh, delimiter="\t")
        if reader.fieldnames is None or "SAMPLE" not in reader.fieldnames:
            sys.exit(f"ERROR: no SAMPLE column in {path}")
        samples = [row["SAMPLE"].strip() for row in reader if row["SAMPLE"]]
    return list(dict.fromkeys(s for s in samples if s))


def build_pairs(
    samples: list[str],
    patient_re: re.Pattern,
    type_re: re.Pattern,
    tumor: str,
    normal: str,
    unmatched_normal: str,
) -> list[tuple[str, str]]:
    """Pair tumors with normals from the same patient.

    Args:
        samples: Sample IDs.
        patient_re: Regex whose group 1 is the patient ID.
        type_re: Regex whose group 1 is the sample type.
        tumor: Sample type value for tumors.
        normal: Sample type value for normals.
        unmatched_normal: NORMAL_ID used for tumors with no normal.

    Returns:
        List of (NORMAL_ID, TUMOR_ID) pairs sorted by patient.
    """
    normals = defaultdict(list)
    tumors = defaultdict(list)

    for sample in samples:
        patient = extract(patient_re, sample)
        stype = extract(type_re, sample)
        if patient is None or stype is None:
            warn(f"{sample}: regex did not match (patient={patient}, type={stype}); skipped")
        elif stype == tumor:
            tumors[patient].append(sample)
        elif stype == normal:
            normals[patient].append(sample)
        else:
            warn(f"{sample}: unknown sample type '{stype}'; skipped")

    pairs = []
    for patient in sorted(set(normals) | set(tumors)):
        pt_normals = sorted(normals[patient])
        pt_tumors = sorted(tumors[patient])
        if not pt_tumors:
            warn(f"{patient}: normal(s) with no tumor: {', '.join(pt_normals)}")
            continue
        if not pt_normals:
            warn(f"{patient}: no normal; paired with {unmatched_normal}")
            pt_normals = [unmatched_normal]
        elif len(pt_normals) > 1:
            warn(f"{patient}: {len(pt_normals)} normals; pairing each tumor with all")
        pairs.extend((n, t) for t in pt_tumors for n in pt_normals)
    return pairs


def main() -> None:
    """Run the script."""
    args = parse_args()
    patient_re = re.compile(args.patient_regex)
    type_re = re.compile(args.type_regex)
    for name, pattern in (("patient_regex", patient_re), ("type_regex", type_re)):
        if pattern.groups < 1:
            sys.exit(f"ERROR: {name} must have a capture group")

    samples = read_samples(args.mapping)
    pairs = build_pairs(
        samples, patient_re, type_re, args.tumor, args.normal, args.unmatched
    )

    out = open(args.output, "w", newline="") if args.output else sys.stdout
    try:
        writer = csv.writer(out, delimiter="\t", lineterminator="\n")
        writer.writerow(["NORMAL_ID", "TUMOR_ID"])
        writer.writerows(pairs)
    finally:
        if args.output:
            out.close()


if __name__ == "__main__":
    main()
