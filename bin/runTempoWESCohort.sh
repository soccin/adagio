#!/bin/bash

OPWD=$PWD
SDIR="$( cd "$( dirname "$0" )" && pwd )"
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
    export NXF_OPTS='-Xms1g -Xmx4g'
    export NXF_SINGULARITY_CACHEDIR=/scratch/core001/bic/socci/opt/singularity/cachedir
    export TMPDIR=/scratch/core001/bic/socci/Adagio/$UUID
    export WORKDIR=/scratch/core001/bic/socci/Adagio/$UUID/run

    PIPELINE_CONFIG=tempo-wes-iris
    REFERENCE_BASE="/data1/core001/rsrc/genomic"

elif [ "$CLUSTER" == "JUNO" ]; then

    CONFIG=neo
    export WORKDIR=work/$UUID
    export NXF_SINGULARITY_CACHEDIR=/rtsess01/compute/juno/bic/ROOT/opt/singularity/cachedir_socci
    export TMPDIR=/scratch/socci

    PIPELINE_CONFIG=tempo-wes-juno
    REFERENCE_BASE="/rtsess01/compute/juno/bic/ROOT/rscr"

else

    echo -e "\nUnknown cluster: $CLUSTER\n"
    exit 1

fi


#
# Use default CMO/MSKCC juno.config
# Put any over-rides in config files in adagio/conf
#
TEMPO_PROFILE=juno

ASSAY_TYPE=exome

TARGETS_BASE="${REFERENCE_BASE}/mskcc-igenomes/grch37/tempo_targets"


set -ue

if [ "$#" -lt "3" ]; then
    echo
    echo usage: runTempoWESCohort.sh PROJECT_ID MAPPING.tsv PAIRING.tsv [AGGREGATE.tsv]
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

nextflow run $ADIR/tempo/dsl2.nf -ansi-log $ANSI_LOG \
    -resume \
    -profile $TEMPO_PROFILE \
    -c $ADIR/conf/${CONFIG}.config \
    -c $ADIR/conf/${PIPELINE_CONFIG}.config \
    --reference_base=$REFERENCE_BASE \
    --targets_base=$TARGETS_BASE \
    --assayType $ASSAY_TYPE \
    --somatic \
    --workflows="snv,qc,facets,msisensor,mutsig" \
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
    --workflows="snv,qc,facets,msisensor,mutsig" \
    --aggregate $AGGREGATE \
    --mapping $MAPPING \
    --pairing $PAIRING \
    --outDir $ODIR
END_VERSION
