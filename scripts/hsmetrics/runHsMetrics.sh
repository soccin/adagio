#!/bin/bash
#SBATCH -J HsMetrics
#SBATCH -o SLM/hsMetrics.%A_%a.out
#SBATCH -c 1
#SBATCH --mem=6G
#SBATCH -t 2:00:00
#SBATCH --partition cpushort,cmobic_short

#
# One sample of doHsMetrics.sh: Picard CollectHsMetrics with a raised
# COVERAGE_CAP. See README.md.
#

usage() {
    cat <<EOF

Usage: sbatch --array=1-N runHsMetrics.sh SHEET
       sbatch runHsMetrics.sh SHEET ROW

Run Picard CollectHsMetrics for one row of a sample sheet written by
doHsMetrics.sh. Submit with doHsMetrics.sh, which writes the sheet and
sets the array size.

The row is SLURM_ARRAY_TASK_ID, or ROW for a single job. Row 1 is the
first sample after the header.

Sheet columns (tab separated, with header):
  SAMPLE BAM BAITS TARGETS FASTA CAP IMAGE ODIR

Output: ODIR/SAMPLE.hs_metrics.txt

EOF
}

for arg in "$@"; do
    if [ "$arg" == "-h" ] || [ "$arg" == "--help" ]; then
        usage
        exit 0
    fi
done

if [ $# -lt 1 ]; then
    usage
    exit 1
fi

set -eu -o pipefail

SHEET=$1
ROW=${2:-${SLURM_ARRAY_TASK_ID:-}}
HEADER=$'SAMPLE\tBAM\tBAITS\tTARGETS\tFASTA\tCAP\tIMAGE\tODIR'

die() {
    echo -e "\nERROR: $*\n" >&2
    exit 1
}

[ -s "$SHEET" ] || die "sample sheet not found: $SHEET"
[[ "$ROW" =~ ^[0-9]+$ ]] || die "no row number: give ROW or submit as an array job"
[ "$(head -1 "$SHEET")" == "$HEADER" ] || die "unexpected header in $SHEET"

LINE=$(awk -v r=$((ROW + 1)) 'NR == r' "$SHEET")
[ -n "$LINE" ] || die "no row $ROW in $SHEET"
IFS=$'\t' read -r SAMPLE BAM BAITS TARGETS FASTA CAP IMAGE ODIR <<< "$LINE"

for f in "$BAM" "$BAITS" "$TARGETS" "$FASTA" "$IMAGE"; do
    [ -e "$f" ] || die "file not found: $f"
done

# Node-local temp space, never the node's /tmp. It is mounted over /tmp
# in the container, and Picard and Java write their temp files there.
JOBTMP=/localscratch/$USER/hsmetrics/${SLURM_JOB_ID:-$$}
mkdir -p "$JOBTMP"
export TMPDIR="$JOBTMP"
export SINGULARITY_TMPDIR="$JOBTMP"
export APPTAINER_TMPDIR="$JOBTMP"
trap 'rm -rf "$JOBTMP"' EXIT

# Java heap: two thirds of the job memory (SLURM gives MB), at least 2 GB
XMX=$(( ${SLURM_MEM_PER_NODE:-6144} * 2 / 3 / 1024 ))
[ "$XMX" -ge 2 ] || XMX=2

BINDS=$(printf '%s\n' "$(dirname "$BAM")" "$(dirname "$BAITS")" \
    "$(dirname "$TARGETS")" "$(dirname "$FASTA")" | sort -u | paste -sd,)

echo "SAMPLE: $SAMPLE"
echo "BAM: $BAM"
echo "COVERAGE_CAP: $CAP"
echo "IMAGE: $IMAGE"
echo "HOST: $(hostname)"
echo "JOB: ${SLURM_JOB_ID:-none} (array ${SLURM_ARRAY_JOB_ID:-none} task ${SLURM_ARRAY_TASK_ID:-none})"
echo "START: $(date)"

singularity exec --cleanenv -B "$JOBTMP:/tmp,$BINDS" "$IMAGE" \
    gatk CollectHsMetrics \
        --java-options "-Xmx${XMX}g -Djava.io.tmpdir=/tmp" \
        --TMP_DIR /tmp \
        --INPUT "$BAM" \
        --OUTPUT "/tmp/$SAMPLE.hs_metrics.txt" \
        --REFERENCE_SEQUENCE "$FASTA" \
        --BAIT_INTERVALS "$BAITS" \
        --TARGET_INTERVALS "$TARGETS" \
        --COVERAGE_CAP "$CAP"

OUT="$JOBTMP/$SAMPLE.hs_metrics.txt"
grep -q "^## METRICS CLASS" "$OUT" || die "no metrics in $OUT"

# The median comes from the capped histogram; at the cap it is still
# capped and the sample needs a higher -c
MEDIAN=$(awk -F'\t' '
    /^## METRICS CLASS/ {
        getline
        for (i = 1; i <= NF; i++) if ($i == "MEDIAN_TARGET_COVERAGE") c = i
        getline
        print $c
        exit
    }' "$OUT")
echo "MEDIAN_TARGET_COVERAGE: $MEDIAN"
if awk -v m="$MEDIAN" -v c="$CAP" 'BEGIN { exit !(m >= c) }'; then
    echo "WARNING: $SAMPLE median target coverage is at COVERAGE_CAP $CAP; rerun with a higher -c"
fi

# Copy then rename, so ODIR never holds a partial file
mkdir -p "$ODIR"
cp "$OUT" "$ODIR/.$SAMPLE.hs_metrics.txt.part"
mv "$ODIR/.$SAMPLE.hs_metrics.txt.part" "$ODIR/$SAMPLE.hs_metrics.txt"

echo "OUTPUT: $ODIR/$SAMPLE.hs_metrics.txt"
echo "END: $(date)"
