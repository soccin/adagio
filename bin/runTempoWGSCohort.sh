#!/bin/bash

set -ue

yq () {
    egrep $1 $2 | sed 's/.*: //' | tr -d '"' | tr -d "'"
}

OPWD=$PWD
SDIR="$( cd "$( dirname "$0" )" && pwd )"
ADIR=$(realpath $SDIR/..)

PROFILE=neo

export NXF_SINGULARITY_CACHEDIR=/rtsess01/compute/juno/bic/ROOT/opt/singularity/cachedir_socci
export TMPDIR=/scratch/socci
export PATH=$ADIR/bin:$PATH

if [ "$#" -lt "3" ]; then
    echo
    echo usage: runTempoWGSCohort.sh PROJECT.yaml MAPPING.tsv PAIRING.tsv [AGGREGATE.tsv]
    echo
    exit
fi

PROJECT=$(realpath $1)
MAPPING=$(realpath $2)
PAIRING=$(realpath $3)
if [ "$#" == "4" ]; then
    AGGREGATE=$(realpath $4)
else
    AGGREGATE=true
fi

PROJECT_ID=$(yq requestId $PROJECT)
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

LOG=${PROJECT_ID}_${TUMOR}_runTempoWGS.log

echo \$RDIR=$(realpath .) >$LOG
echo \$ODIR=$ODIR >>$LOG

nextflow run $ADIR/tempo/dsl2.nf -ansi-log false \
    -profile $PROFILE \
    --assayType genome \
    --somatic \
    --workflows="snv,sv,qc,facets,msisensor,mutsig" \
    --aggregate $AGGREGATE \
    --mapping $MAPPING \
    --pairing $PAIRING \
    --outDir $ODIR \
    >> $LOG 2> ${LOG/.log/.err}

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

Script: $0 $*

nextflow run $ADIR/tempo/dsl2.nf -ansi-log false \
    -profile $PROFILE \
    --assayType genome \
    --somatic \
    --workflows="snv,sv,qc,facets,msisensor,mutsig" \
    --aggregate $AGGREGATE \
    --mapping $MAPPING \
    --pairing $PAIRING \
    --outDir $ODIR

END_VERSION
