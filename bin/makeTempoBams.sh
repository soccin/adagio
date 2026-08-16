#!/bin/bash
#SBATCH -J Adagio-BAMs
#SBATCH -o SLM/adagioBams.%j.out
#SBATCH -c 4
#SBATCH -t 7-00:00:00
#SBATCH --partition cmobic_cpu,bic_devs

#
# Build recalibrated BAMs from FASTQs using only Tempo's alignment
# sub-workflow: no pairing, no variant calling, no aggregation.
#
# Tempo enables alignment whenever --mapping is given (dsl2.nf,
# doWF_align). Passing an empty --workflows= leaves the workflow list
# empty -- the one value that lets a run proceed without a --pairing
# file. --qc swaps that for --workflows=qc, the only other value the
# no-pairing guard accepts.
#
# Outputs, both under out/$PROJECT_ID:
#   bams/<SAMPLE>/<SAMPLE>.bam       BQSR-recalibrated, indexed
#   <PROJECT_ID>_bamMapping.tsv      SAMPLE/TARGET/BAM/BAI, ready to
#                                    feed to runTempoWGSBam.sh
#

OPWD=$PWD

# Vanilla sbatch runs scripts from a temp folder copy, breaking
# relative paths. I have an sbatch wrapper (~/bin/sbatch) that
# preserves the original directory via:
#   sbatch --export=SBATCH_SCRIPT_DIR="$SCRIPT_DIR"
# allowing jobs to access their original location through
# $SBATCH_SCRIPT_DIR for proper path resolution.
#
if [ -n "$SBATCH_SCRIPT_DIR" ]; then
    SDIR="$SBATCH_SCRIPT_DIR"
else
    SDIR="$( cd "$( dirname "$0" )" && pwd )"
fi

ADIR=$(realpath $SDIR/..)
export PATH=$ADIR/bin:$PATH

haveNextflow=$(which nextflow 2>/dev/null)

if [ "$haveNextflow" == "" ]; then
    echo -e "\n\n   Need to install nextflow; see adagio/docs\n\n"
    exit 1
fi

DS=$(date +%Y%m%d_%H%M%S)
UUID=${DS}_${RANDOM}

. $ADIR/bin/getClusterName.sh
echo \$CLUSTER=$CLUSTER
if [ "$CLUSTER" == "IRIS" ]; then

    CONFIG=iris
    TEMPO_PROFILE=iris

    export NXF_OPTS='-Xms1g -Xmx4g'
    export NXF_SINGULARITY_CACHEDIR=/scratch/core001/bic/socci/opt/singularity/cachedir
    export TMPDIR=/scratch/core001/bic/socci/Adagio/$UUID
    export WORKDIR=/scratch/core001/bic/socci/Adagio/$UUID/run

    REFERENCE_BASE="/data1/core001/rsrc/genomic"


elif [ "$CLUSTER" == "JUNO" ]; then

    CONFIG=juno
    TEMPO_PROFILE=juno

    export NXF_OPTS='-Xms1g -Xmx4g'
    export WORKDIR=work/$UUID
    export NXF_SINGULARITY_CACHEDIR=/rtsess01/compute/juno/bic/ROOT/opt/singularity/cachedir_socci
    export TMPDIR=/scratch/socci

    REFERENCE_BASE="/rtsess01/compute/juno/bic/ROOT/rscr"

else

    echo -e "\nUnknown cluster: $CLUSTER\n"
    exit 1

fi

TARGETS_BASE="${REFERENCE_BASE}/mskcc-igenomes/grch37/tempo_targets"


set -ue

#
# Defaults
#
ASSAY=genome
RUN_QC=false
ANONYMIZE=false

#
# Parse optional arguments
#
while [[ $# -gt 0 ]]; do
    case $1 in
        --assay=*)
            ASSAY="${1#*=}"
            shift
            ;;
        --qc)
            # Adds sampleQC_wf (qualimap, alfred, MultiQC) on top of
            # alignment. Allowed without pairing; roughly doubles the
            # per-sample compute.
            RUN_QC=true
            shift
            ;;
        --anonymize)
            # Anonymizes FASTQ read IDs before alignment.
            ANONYMIZE=true
            shift
            ;;
        *)
            break
            ;;
    esac
done

if [ "$#" -lt "2" ]; then
    echo
    echo usage: makeTempoBams.sh [--assay=genome\|exome] [--qc] [--anonymize] PROJECT_ID MAPPING.tsv
    echo
    echo "  --assay=genome|exome  Assay type (default: genome)"
    echo "  --qc                  Also run the qc workflow on the new BAMs"
    echo "  --anonymize           Pass --anonymizeFQ to Tempo"
    echo
    echo "  MAPPING.tsv columns: SAMPLE TARGET FASTQ_PE1 FASTQ_PE2"
    echo "    TARGET must be 'wgs' for --assay=genome, a bait set otherwise"
    echo
    exit
fi

#
# Assay picks both the Tempo assayType and the resource config; the two
# must agree, so they are set together and nowhere else.
#
if [ "$ASSAY" == "genome" ]; then
    ASSAY_TYPE=genome
    PIPELINE_CONFIG=tempo-wgs-${CONFIG}
elif [ "$ASSAY" == "exome" ]; then
    ASSAY_TYPE=exome
    PIPELINE_CONFIG=tempo-wes-${CONFIG}
else
    echo -e "\nInvalid --assay=$ASSAY; must be genome or exome\n"
    exit 1
fi

#
# WFs == [''] is what dsl2.nf needs to skip every downstream workflow
# without a pairing file; 'qc' is the only other value its guard lets
# through unpaired.
#
# It has to be the empty string, not "false". Both reach WFs == ['']
# while Nextflow's CLI type detection is on -- "false" arrives as a
# Boolean, which dsl2.nf:58 maps to '' -- but under
# NXF_DISABLE_PARAMS_TYPE_DETECTION=true "false" stays a String and
# splits to ['false'], which trips the no-pairing guard and aborts
# before alignment. An empty value is a String in both modes.
#
if [ "$RUN_QC" == "true" ]; then
    WORKFLOWS=qc
else
    WORKFLOWS=""
fi

if [ "$ANONYMIZE" == "true" ]; then
    NF_PARAMS="--anonymizeFQ"
else
    NF_PARAMS=""
fi

PROJECT_ID=$1
MAPPING=$(realpath $2)

ODIR=$(pwd -P)/out/${PROJECT_ID}
BAM_MAPPING=${ODIR}/${PROJECT_ID}_bamMapping.tsv

echo \$ODIR=$ODIR

#
# alignment_wf opens --outname as soon as the workflow is built, so
# $ODIR has to exist before nextflow starts.
#
mkdir -p $ODIR
mkdir -p $WORKDIR
pushd $WORKDIR

RUNDIR=$(pwd -P)
LOG=${PROJECT_ID}_makeTempoBams.log

echo \$WORKDIR=$RUNDIR >$LOG
echo \$ODIR=$ODIR >>$LOG

#
# Check if in backgroup or forground
#
# https://unix.stackexchange.com/questions/118462/how-can-a-bash-script-detect-if-it-is-running-in-the-background
#

case $(ps -o stat= -p $$) in
  *+*) ANSI_LOG="true" ;;
  *) ANSI_LOG="false" ;;
esac

nextflow run $ADIR/tempo/dsl2.nf -ansi-log $ANSI_LOG \
    -resume \
    -profile $TEMPO_PROFILE \
    -c $ADIR/conf/${CONFIG}.config \
    -c $ADIR/conf/${PIPELINE_CONFIG}.config \
    --reference_base=$REFERENCE_BASE \
    --targets_base=$TARGETS_BASE \
    --assayType $ASSAY_TYPE \
    --workflows=$WORKFLOWS \
    --mapping $MAPPING \
    --outDir $ODIR \
    --outname $BAM_MAPPING \
    $NF_PARAMS \
    2> ${LOG/.log/.err} \
    | tee -a $LOG

#
# The pipe means $? is tee's, so set -e never sees a nextflow failure.
# Grab nextflow's own status before anything else clobbers PIPESTATUS.
#
NF_EXIT=${PIPESTATUS[0]}

mkdir -p $ODIR/runlog

cp $MAPPING $ODIR/runlog

GTAG=$(git --git-dir=$ADIR/.git --work-tree=$ADIR describe --long --tags --dirty="-UNCOMMITED" --always)
GURL=$(git --git-dir=$ADIR/.git --work-tree=$ADIR config --get remote.origin.url)

cat <<-END_VERSION > $ODIR/runlog/cmd.sh.log
ADIR: $ADIR
CLUSTER: $CLUSTER
GURL: $GURL
GTAG: $GTAG
PWD: $OPWD
ODIR: $ODIR
WORKDIR: $WORKDIR
UUID: $UUID
PROJECT_ID: $PROJECT_ID
TEMPO_PROFILE: $TEMPO_PROFILE
ASSAY_TYPE: $ASSAY_TYPE
REFERENCE_BASE: $REFERENCE_BASE
TARGETS_BASE: $TARGETS_BASE
WORKFLOWS: $WORKFLOWS
BAM_MAPPING: $BAM_MAPPING
NF_EXIT: $NF_EXIT

Script: $0 $*

nextflow run $ADIR/tempo/dsl2.nf -ansi-log $ANSI_LOG \
    -resume \
    -profile $TEMPO_PROFILE \
    -c $ADIR/conf/${CONFIG}.config \
    -c $ADIR/conf/${PIPELINE_CONFIG}.config \
    --reference_base=$REFERENCE_BASE \
    --targets_base=$TARGETS_BASE \
    --assayType $ASSAY_TYPE \
    --workflows=$WORKFLOWS \
    --mapping $MAPPING \
    --outDir $ODIR \
    --outname $BAM_MAPPING \
    $NF_PARAMS
END_VERSION

popd

#
# Run the trace report either way -- it is most useful on a failure --
# then report the real outcome.
#
Rscript $ADIR/scripts/nfTraceReport.R | tee RUN_REPORT_$(date +%y%m%d)_.md

if [ "$NF_EXIT" != "0" ]; then
    echo
    echo "ERROR: nextflow exited $NF_EXIT; run did not complete"
    echo "  $BAM_MAPPING is missing or covers only the samples that finished"
    echo "  stderr: $RUNDIR/${LOG/.log/.err}"
    echo
    exit $NF_EXIT
fi

echo
echo "BAM mapping written to $BAM_MAPPING"
echo
