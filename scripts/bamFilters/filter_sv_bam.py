#!/usr/bin/env python3
"""
filter_sv_bam.py — filter a BAM for SV calling.

Removes: duplicates, QC-fail, secondary alignments,
         pairs where both mates are unmapped.
Keeps:   supplementary alignments (split-read evidence),
         one-end-anchored pairs, soft-clipped and discordant reads.

Usage: filter_sv_bam.py input.bam [--threads N]
Output: input.flt.bam (+ .bai index)
"""

import argparse
import sys
from pathlib import Path

import pysam

# 256 (secondary) + 512 (qcfail) + 1024 (duplicate)
EXCLUDE_MASK = (
    pysam.FSECONDARY | pysam.FQCFAIL | pysam.FDUP
)


def head_has_duplicates(bam_path: str, n_records: int = 1_000_000) -> bool:
    """Scan the first n_records for any duplicate-flagged read."""
    with pysam.AlignmentFile(bam_path, "rb") as bam:
        for i, read in enumerate(bam.fetch(until_eof=True)):
            if read.is_duplicate:
                return True
            if i >= n_records:
                break
    return False


def filter_bam(in_path: str, out_path: str, threads: int) -> dict:
    stats = {"total": 0, "kept": 0, "flag_filtered": 0, "both_unmapped": 0}

    with pysam.AlignmentFile(in_path, "rb", threads=threads) as bam_in, \
         pysam.AlignmentFile(out_path, "wb", template=bam_in,
                             threads=threads) as bam_out:
        for read in bam_in.fetch(until_eof=True):
            stats["total"] += 1

            if read.flag & EXCLUDE_MASK:
                stats["flag_filtered"] += 1
                continue

            # Drop only pairs where BOTH mates are unmapped.
            # Unpaired unmapped reads carry no SV evidence either.
            if read.is_unmapped:
                if not read.is_paired or read.mate_is_unmapped:
                    stats["both_unmapped"] += 1
                    continue

            bam_out.write(read)
            stats["kept"] += 1

    return stats


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bam", help="input BAM file")
    parser.add_argument("--threads", type=int, default=4,
                        help="threads for BAM (de)compression [4]")
    args = parser.parse_args()

    in_path = Path(args.bam)
    if not in_path.is_file():
        sys.exit(f"ERROR: {in_path} not found")
    if in_path.suffix != ".bam":
        sys.exit("ERROR: input must end in .bam")

    out_path = in_path.with_suffix(".flt.bam")
    if out_path == in_path:
        sys.exit("ERROR: output would overwrite input")

    if not head_has_duplicates(str(in_path)):
        print("WARNING: no duplicate-flagged reads found at start of file.",
              file=sys.stderr)
        print("WARNING: if duplicates were never marked, run markdup first, "
              "or this script removes none.", file=sys.stderr)

    print(f"Filtering {in_path} -> {out_path}")
    stats = filter_bam(str(in_path), str(out_path), args.threads)

    print(f"Indexing {out_path}")
    pysam.index("-@", str(args.threads), str(out_path))

    total = stats["total"] or 1
    print(f"total reads:      {stats['total']:>14,}")
    print(f"kept:             {stats['kept']:>14,} "
          f"({100 * stats['kept'] / total:.1f}%)")
    print(f"flag-filtered:    {stats['flag_filtered']:>14,}")
    print(f"both-unmapped:    {stats['both_unmapped']:>14,}")


if __name__ == "__main__":
    main()
