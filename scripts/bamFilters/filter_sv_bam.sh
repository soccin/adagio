#!/usr/bin/env bash
set -euo pipefail

# Usage: filter_sv_bam.sh input.bam [threads]
# Removes: duplicates (1024), QC-fail (512), secondary (256),
#          pairs with both mates unmapped.
# Keeps:   supplementary alignments (split-read evidence),
#          one-end-anchored pairs, soft-clipped and discordant reads.

BAM=${1:?Usage: $0 input.bam [threads]}
THREADS=${2:-4}

[[ -f "$BAM" ]] || { echo "ERROR: $BAM not found" >&2; exit 1; }
[[ "$BAM" == *.bam ]] || { echo "ERROR: input must end in .bam" >&2; exit 1; }

OUT=$(basename ${BAM/%.bam/.flt.bam})
[[ "$OUT" != "$BAM" ]] || { echo "ERROR: output would overwrite input" >&2; exit 1; }

# samtools >= 1.12 required for -e filter expressions
SAMTOOLS_VER=$(samtools --version | head -n1 | awk '{print $2}')
echo "samtools $SAMTOOLS_VER"

# Sanity check: -F 1024 is a no-op if duplicates were never marked.
# Scan the first 1M records for a duplicate flag.
DUPSEEN=$( (samtools view -f 1024 "$BAM" 2>/dev/null || true) | head -n 1 | wc -l )
if [[ "$DUPSEEN" -eq 0 ]]; then
    echo "WARNING: no duplicate-flagged reads found at start of file." >&2
    echo "WARNING: if duplicates were never marked, run samtools markdup" >&2
    echo "WARNING: (or Picard MarkDuplicates) first, or this script removes none." >&2
fi

echo "Filtering $BAM -> $OUT"
samtools view -b -@ "$THREADS" \
    -F 1792 \
    -e '!(flag.unmap && flag.munmap)' \
    -o "$OUT" \
    "$BAM"

samtools index -@ "$THREADS" "$OUT"

echo "Done."
ls -lh "$BAM" "$OUT"
