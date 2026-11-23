#!/bin/bash
#
# Submit Picard CollectHsMetrics, with a raised COVERAGE_CAP, for every
# sample of a finished adagio WES run. Tempo runs it with Picard's
# default cap of 200, which caps MEDIAN_TARGET_COVERAGE and the coverage
# histogram at 200x. See README.md.
#

SDIR="$( cd "$( dirname "$0" )" && pwd )"

CAP=1000
PROJECT=""
ODIR=""
MAXJOBS=100
IMAGE=${NXF_SINGULARITY_CACHEDIR:-/scratch/core001/bic/socci/opt/singularity/cachedir}/broadinstitute-gatk-4.1.0.0.img
FASTA=""
SAMPLES=""
FORCE=0
DRYRUN=0

usage() {
    cat <<EOF

Usage: doHsMetrics.sh [-p PROJECT_ID] [-c CAP] [-o ODIR] [-s S1,S2,...]
                      [-m MAXJOBS] [-i IMAGE] [-r FASTA] [-f] [-n]

Run Picard CollectHsMetrics (GATK 4.1.0.0, as in Tempo) on the BAM of
every sample of a finished adagio WES run, with COVERAGE_CAP raised from
200 to CAP. Run from the project folder (the one that holds out/). It
submits one SLURM array task per sample (runHsMetrics.sh) and returns.

Inputs come from the run log out/<PROJECT_ID>/runlog/cmd.sh.log: the
mapping file (sample and target), TARGETS_BASE (bait and target
intervals) and REFERENCE_BASE (GRCh37 FASTA). BAMs are read from
out/<PROJECT_ID>/bams/<SAMPLE>/<SAMPLE>.bam, or from the BAM column of
the mapping file.

Output: ODIR/<SAMPLE>.hs_metrics.txt, the same format as Tempo's file.
Samples that already have output are skipped unless -f is given.

Options:
  -p PROJECT_ID  the run under out/ to use (needed only when out/ holds
              more than one run)
  -c CAP      COVERAGE_CAP (default $CAP). Picard caps MEDIAN_TARGET_COVERAGE,
              the coverage histogram and the FOLD_80_BASE_PENALTY percentile
              at CAP. HET_SNP_SENSITIVITY only uses depths up to 1000, so a
              CAP above 1000 lowers it slightly; raise CAP only for samples
              whose median reaches it (the job log warns).
  -o ODIR     output folder (default out/<PROJECT_ID>/post/qc)
  -s SAMPLES  only these samples, comma separated
  -m MAXJOBS  array tasks running at once (default $MAXJOBS)
  -i IMAGE    GATK Singularity image (default
              $IMAGE)
  -r FASTA    reference FASTA (default: GRCh37 under REFERENCE_BASE)
  -f          redo samples that already have output
  -n          dry run: list the samples and the sbatch command, write nothing
  -h          this help

EOF
}

for arg in "$@"; do
    if [ "$arg" == "--help" ]; then
        usage
        exit 0
    fi
done

while getopts "p:c:o:s:m:i:r:fnh" opt; do
    case $opt in
        p) PROJECT=$OPTARG ;;
        c) CAP=$OPTARG ;;
        o) ODIR=$OPTARG ;;
        s) SAMPLES=$OPTARG ;;
        m) MAXJOBS=$OPTARG ;;
        i) IMAGE=$OPTARG ;;
        r) FASTA=$OPTARG ;;
        f) FORCE=1 ;;
        n) DRYRUN=1 ;;
        h) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

if [ $# -gt 0 ]; then
    usage
    exit 1
fi

set -eu -o pipefail

die() {
    echo -e "\nERROR: $*\n" >&2
    exit 1
}

[[ "$CAP" =~ ^[0-9]+$ ]] && [ "$CAP" -ge 1 ] || die "-c CAP must be a positive integer"
[[ "$MAXJOBS" =~ ^[0-9]+$ ]] && [ "$MAXJOBS" -ge 1 ] || die "-m MAXJOBS must be a positive integer"
[ -e "$IMAGE" ] || die "GATK image not found: $IMAGE"

#
# Run log
#
if [ -n "$PROJECT" ]; then
    CMDLOG=out/$PROJECT/runlog/cmd.sh.log
    [ -e "$CMDLOG" ] || die "no $CMDLOG; run from the project folder"
else
    shopt -s nullglob
    CMDLOGS=(out/*/runlog/cmd.sh.log)
    shopt -u nullglob
    [ ${#CMDLOGS[@]} -gt 0 ] || die "no out/*/runlog/cmd.sh.log; run from the project folder"
    [ ${#CMDLOGS[@]} -eq 1 ] || die "more than one run under out/ (use -p): ${CMDLOGS[*]}"
    CMDLOG=${CMDLOGS[0]}
fi
RUNLOG=$(dirname "$CMDLOG")
RUNDIR=$(dirname "$RUNLOG")

log_value() {
    awk -v k="$1:" '$1 == k { print $2; exit }' "$CMDLOG"
}

# Value of a nextflow option (--opt value or --opt=value) in the run log
nf_option() {
    awk -v o="--$1" '{
        for (i = 1; i <= NF; i++) {
            if ($i == o && i < NF) { print $(i + 1); exit }
            if (index($i, o "=") == 1) { print substr($i, length(o) + 2); exit }
        }
    }' "$CMDLOG"
}

ASSAY=$(log_value ASSAY_TYPE)
[ "$ASSAY" == "exome" ] || die "ASSAY_TYPE is '$ASSAY' in $CMDLOG; CollectHsMetrics needs bait intervals (exome only)"

REFERENCE_BASE=$(log_value REFERENCE_BASE)
TARGETS_BASE=$(log_value TARGETS_BASE)
[ -n "$TARGETS_BASE" ] || TARGETS_BASE=$(nf_option targets_base)
[ -n "$TARGETS_BASE" ] || TARGETS_BASE=$REFERENCE_BASE/mskcc-igenomes/grch37/tempo_targets
[ -d "$TARGETS_BASE" ] || die "TARGETS_BASE not found: $TARGETS_BASE"

if [ -z "$FASTA" ]; then
    GENOME=$(nf_option genome)
    if [ -n "$GENOME" ] && [ "$GENOME" != "GRCh37" ]; then
        die "run used --genome $GENOME; give its FASTA with -r"
    fi
    FASTA=$REFERENCE_BASE/mskcc-igenomes/igenomes/Homo_sapiens/GATK/GRCh37/Sequence/WholeGenomeFasta/human_g1k_v37_decoy.fasta
fi
[ -e "$FASTA" ] || die "reference FASTA not found: $FASTA"

#
# Mapping file: the runlog copy of the --mapping file, as
# scripts/rsrc/read_pairing.R does for the pairing
#
MAPPATH=$(nf_option mapping)
[ -n "$MAPPATH" ] || die "no --mapping in $CMDLOG"
MAPPING=$RUNLOG/$(basename "$MAPPATH")
[ -e "$MAPPING" ] || MAPPING=$MAPPATH
[ -e "$MAPPING" ] || die "mapping file not found: $RUNLOG/$(basename "$MAPPATH") or $MAPPATH"

# One row per sample: SAMPLE, TARGET, BAM (empty if no BAM column)
SAMPLE_TABLE=$(awk -F'\t' '
    { sub(/\r$/, "") }
    NR == 1 {
        for (i = 1; i <= NF; i++) col[$i] = i
        if (!col["SAMPLE"] || !col["TARGET"]) {
            print "ERROR: no SAMPLE or TARGET column in " FILENAME > "/dev/stderr"
            exit 2
        }
        next
    }
    !seen[$col["SAMPLE"] "\t" $col["TARGET"]]++ {
        print $col["SAMPLE"] "\t" $col["TARGET"] "\t" (col["BAM"] ? $col["BAM"] : "")
    }' "$MAPPING")

DUPS=$(cut -f1 <<< "$SAMPLE_TABLE" | sort | uniq -d | paste -sd' ')
[ -z "$DUPS" ] || die "samples with more than one TARGET in $MAPPING: $DUPS"

if [ -n "$SAMPLES" ]; then
    IFS=',' read -ra SLIST <<< "$SAMPLES"
    for s in "${SLIST[@]}"; do
        awk -F'\t' -v s="$s" '$1 == s { f = 1 } END { exit !f }' <<< "$SAMPLE_TABLE" \
            || die "sample $s not in $MAPPING"
    done
fi

#
# Sample sheet rows
#
[ -n "$ODIR" ] || ODIR=$RUNDIR/post/qc
ODIR_ABS=$(realpath -m "$ODIR")
ROWS=""
NDONE=0
ERRORS=0

while IFS=$'\t' read -r SAMPLE TARGET MAPBAM; do

    if [ -n "$SAMPLES" ]; then
        case ",$SAMPLES," in
            *",$SAMPLE,"*) ;;
            *) continue ;;
        esac
    fi

    if [ -e "$ODIR/$SAMPLE.hs_metrics.txt" ] && [ "$FORCE" -eq 0 ]; then
        NDONE=$((NDONE + 1))
        continue
    fi

    BAM=$RUNDIR/bams/$SAMPLE/$SAMPLE.bam
    [ -e "$BAM" ] || BAM=$MAPBAM
    BAITS=$TARGETS_BASE/$TARGET/baits.interval_list
    TARGETS=$TARGETS_BASE/$TARGET/targets.interval_list

    if [ -z "$BAM" ] || [ ! -e "$BAM" ]; then
        echo "ERROR: no BAM for $SAMPLE ($RUNDIR/bams/$SAMPLE/$SAMPLE.bam)" >&2
        ERRORS=$((ERRORS + 1))
        continue
    fi
    if [ ! -e "$BAITS" ] || [ ! -e "$TARGETS" ]; then
        echo "ERROR: no intervals for target $TARGET of $SAMPLE in $TARGETS_BASE/$TARGET" >&2
        ERRORS=$((ERRORS + 1))
        continue
    fi

    # Resolve links: Picard names BAIT_SET after the bait file, and the
    # real folders are the ones mounted in the container
    ROWS+=$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' "$SAMPLE" "$(realpath "$BAM")" \
        "$(realpath "$BAITS")" "$(realpath "$TARGETS")" "$(realpath "$FASTA")" \
        "$CAP" "$(realpath "$IMAGE")" "$ODIR_ABS")$'\n'

done <<< "$SAMPLE_TABLE"

[ "$ERRORS" -eq 0 ] || die "$ERRORS sample(s) with missing inputs; nothing submitted"

N=$(grep -c . <<< "$ROWS" || true)

echo "Run log: $CMDLOG"
echo "Mapping: $MAPPING"
echo "Targets: $TARGETS_BASE"
echo "FASTA: $FASTA"
echo "Image: $IMAGE"
echo "COVERAGE_CAP: $CAP"
echo "Output: $ODIR_ABS"
echo "Samples to run: $N (already done, skipped: $NDONE)"

if [ "$N" -eq 0 ]; then
    echo "Nothing to run."
    exit 0
fi

ARRAY="1-$N%$MAXJOBS"

if [ "$DRYRUN" -eq 1 ]; then
    echo
    awk -F'\t' 'NR <= 5 { print $1 "\t" $2 }' <<< "$ROWS"
    [ "$N" -le 5 ] || echo "... ($N samples)"
    echo
    echo "sbatch --parsable --array=$ARRAY $SDIR/runHsMetrics.sh $ODIR_ABS/runlog/samples_<timestamp>.tsv"
    exit 0
fi

# A new sheet for each submission: tasks of an earlier array that is
# still running keep reading their own sheet
mkdir -p "$ODIR_ABS/runlog"
SHEET=$ODIR_ABS/runlog/samples_$(date +%Y%m%d_%H%M%S).tsv
{
    printf 'SAMPLE\tBAM\tBAITS\tTARGETS\tFASTA\tCAP\tIMAGE\tODIR\n'
    printf '%s' "$ROWS"
} > "$SHEET"

# cpushort accepts only QoS normal (docs/IRIS_SLURM.md section 5)
unset SBATCH_QOS
JOBID=$(sbatch --parsable --array="$ARRAY" "$SDIR/runHsMetrics.sh" "$SHEET")

echo "Sheet: $SHEET"
echo "Submitted array job $JOBID ($ARRAY); logs in SLM/hsMetrics.${JOBID}_<task>.out"
