#!/bin/bash
#SBATCH -J Adagio-WES
#SBATCH -o SLM/adagioWES.%j.out
#SBATCH -c 4
#SBATCH -t 7-00:00:00
#SBATCH --partition cmobic_cpu,cmobic_pipeline

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

    export WORKDIR=work/$UUID
    export NXF_SINGULARITY_CACHEDIR=/rtsess01/compute/juno/bic/ROOT/opt/singularity/cachedir_socci
    export TMPDIR=/scratch/socci

    REFERENCE_BASE="/rtsess01/compute/juno/bic/ROOT/rscr"

else

    echo -e "\nUnknown cluster: $CLUSTER\n"
    exit 1

fi


#
# Use default CMO/MSKCC juno.config
# Put any over-rides in config files in adagio/conf
#

PIPELINE_CONFIG=tempo-wes-${CONFIG}
ASSAY_TYPE=exome

TARGETS_BASE="${REFERENCE_BASE}/mskcc-igenomes/grch37/tempo_targets"


set -ue

#
# Default workflows
#
DEFAULT_WORKFLOWS=snv,qc,facets
WORKFLOWS=$DEFAULT_WORKFLOWS
WORKFLOW_MODE="default"

#
# Parse optional workflow arguments
#
while [[ $# -gt 0 ]]; do
    case $1 in
        --workflows=*)
            WORKFLOWS="${1#*=}"
            WORKFLOW_MODE="replace"
            shift
            ;;
        --add-workflows=*)
            ADD_WORKFLOWS="${1#*=}"
            WORKFLOWS="${DEFAULT_WORKFLOWS},${ADD_WORKFLOWS}"
            WORKFLOW_MODE="add"
            shift
            ;;
        *)
            break
            ;;
    esac
done

if [ "$#" -lt "3" ]; then
    echo
    echo usage: runTempoWESCohort.sh [--workflows=W1,W2,...] [--add-workflows=W3,W4,...] PROJECT_ID MAPPING.tsv PAIRING.tsv [AGGREGATE.tsv]
    echo
    echo "  --workflows=W1,W2,...      Replace default workflows (default: snv,qc,facets)"
    echo "  --add-workflows=W3,W4,...  Add to default workflows"
    echo
    echo "  Available workflows:"
    echo "    Somatic: snv, sv, mutsig, lohhla, facets, msisensor"
    echo "    Germline: germsnv, germsv"
    echo "    QC: qc"
    echo
    exit
fi

PROJECT_ID=$1
MAPPING=$(realpath $2)
PAIRING=$(realpath $3)
if [ "$#" == "4" ]; then
    AGGREGATE=$(realpath $4)
else
    AGGREGATE=true
fi

ODIR=$(pwd -P)/out/${PROJECT_ID}

echo \$ODIR=$ODIR

mkdir -p $WORKDIR
cd $WORKDIR

LOG=${PROJECT_ID}_runTempoWESCohort.log

echo \$WORKDIR=$(realpath .) >$LOG
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

#
# Full workflow options
#   Somatic: --workflows="snv,sv,qc,facets,msisensor,mutsig,lohhla"
#   Germline: --workflows="germsnv,germsv,qc"
#
# WORKFLOWS is now set earlier based on command-line arguments

nextflow run $ADIR/tempo/dsl2.nf -ansi-log $ANSI_LOG \
    -resume \
    -profile $TEMPO_PROFILE \
    -c $ADIR/conf/${CONFIG}.config \
    -c $ADIR/conf/${PIPELINE_CONFIG}.config \
    --reference_base=$REFERENCE_BASE \
    --targets_base=$TARGETS_BASE \
    --assayType $ASSAY_TYPE \
    --somatic \
    --workflows=$WORKFLOWS \
    --aggregate $AGGREGATE \
    --mapping $MAPPING \
    --pairing $PAIRING \
    --outDir $ODIR \
    2> ${LOG/.log/.err} \
    | tee -a $LOG

mkdir -p $ODIR/runlog

cp $MAPPING $PAIRING $ODIR/runlog
if [ "$AGGREGATE" != "true" ]; then
    cp $AGGREGATE $ODIR/runlog
fi

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
DEFAULT_WORKFLOWS: $DEFAULT_WORKFLOWS
WORKFLOWS: $WORKFLOWS
WORKFLOW_MODE: $WORKFLOW_MODE

Script: $0 $*

nextflow run $ADIR/tempo/dsl2.nf -ansi-log $ANSI_LOG \
    -resume \
    -profile $TEMPO_PROFILE \
    -c $ADIR/conf/${CONFIG}.config \
    -c $ADIR/conf/${PIPELINE_CONFIG}.config \
    --reference_base=$REFERENCE_BASE \
    --targets_base=$TARGETS_BASE \
    --assayType $ASSAY_TYPE \
    --somatic \
    --workflows=$WORKFLOWS \
    --aggregate $AGGREGATE \
    --mapping $MAPPING \
    --pairing $PAIRING \
    --outDir $ODIR
END_VERSION
