#!/bin/bash

OPWD=$PWD
SDIR="$( cd "$( dirname "$0" )" && pwd )"
ADIR=$(realpath $SDIR/..)

#
# Use default CMO/MSKCC juno.config
# Put any over-rides in config files in adagio/conf
#
PROFILE=juno

export NXF_SINGULARITY_CACHEDIR=/rtsess01/compute/juno/bic/ROOT/opt/singularity/cachedir_socci
export TMPDIR=/scratch/socci
export PATH=$ADIR/bin:$PATH

haveNextflow=$(which nextflow 2>/dev/null)

if [ "$haveNextflow" == "" ]; then
    echo -e "\n\n   Need to install nextflow; see adagio/docs\n\n"
    exit 1
fi

set -ue

if [ "$#" -lt "3" ]; then
    echo
    echo usage: runTempoWES.sh PROJECT_ID MAPPING.tsv PAIRING.tsv [AGGREGATE.tsv]
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

TUMOR=$(cat $PAIRING | transpose.py | fgrep TUMOR_ID | cut -f2)
NORMAL=$(cat $PAIRING | transpose.py | fgrep NORMAL_ID | cut -f2)

ODIR=$(pwd -P)/out/${PROJECT_ID}

#
# Need each instance to run in its own directory
#
TUID=$(date +"%Y%m%d_%H%M%S")_$(uuidgen | sed 's/-.*//')
RDIR=run/$PROJECT_ID/$TUID

mkdir -p $RDIR
cd $RDIR

LOG=${PROJECT_ID}_${TUMOR}_runTempoWES.log

echo \$RDIR=$(realpath .) >$LOG
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
    -profile $PROFILE \
    --assayType exome \
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
GURL: $GURL
GTAG: $GTAG
PWD: $OPWD
RDIR: $RDIR
ODIR: $ODIR
PROJECT_ID: $PROJECT_ID

Script: $0 $*

nextflow run $ADIR/tempo/dsl2.nf -ansi-log $ANSI_LOG \
    -profile $PROFILE \
    --assayType exome \
    --somatic \
    --workflows="snv,qc,facets,msisensor,mutsig" \
    --aggregate $AGGREGATE \
    --mapping $MAPPING \
    --pairing $PAIRING \
    --outDir $ODIR
    
END_VERSION
