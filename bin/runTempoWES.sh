#!/bin/bash

yq () {
    egrep $1 $2 | sed 's/.*: //' | tr -d '"' | tr -d "'"
}

OPWD=$PWD
SDIR="$( cd "$( dirname "$0" )" && pwd )"
ADIR=$(realpath $SDIR/..)

export NXF_SINGULARITY_CACHEDIR=/rtsess01/compute/juno/bic/ROOT/opt/singularity/cachedir_socci
export TMPDIR=/scratch/socci
export PATH=$ADIR/bin:$PATH

if [ "$#" != "3" ]; then
    echo
    echo usage: runTempoWES.sh PROJECT.yaml MAPPING.tsv PAIRING.tsv
    echo
    exit
fi

PROJECT=$(realpath $1)
MAPPING=$(realpath $2)
PAIRING=$(realpath $3)

PROJECT_ID=$(yq requestId $PROJECT)
TUMOR=$(cat $PAIRING | transpose.py | fgrep TUMOR_ID | cut -f2)
NORMAL=$(cat $PAIRING | transpose.py | fgrep NORMAL_ID | cut -f2)

ODIR=$(pwd -P)/out/${PROJECT_ID}/${TUMOR}_${NORMAL}

#
# Need each instance to run in its own directory
#
RDIR=run/$PROJECT_ID/${TUMOR}_${NORMAL}

mkdir -p $RDIR
cd $RDIR

LOG=${PROJECT_ID}_${TUMOR}_runTempoWES.log

echo \$RDIR=$(realpath .) >$LOG
echo \$ODIR=$ODIR >>$LOG

#    --workflows="snv,qc,facets,msisensor" \

nextflow run $ADIR/tempo/dsl2.nf -ansi-log false \
    -profile jurassic \
    --scatterCount=5 \
    --assayType exome \
    --somatic \
    --workflows="snv,qc,facets,msisensor,mutsig" \
    --aggregate true \
    --mapping $MAPPING \
    --pairing $PAIRING \
    --outDir $ODIR \
    >> $LOG 2> ${LOG/.log/.err}

cat <<-END_VERSION > $ODIR/cmd.sh.log
SDIR: $SDIR
ADIR: $ADIR
Script: $0 $*

nextflow run $ADIR/tempo/dsl2.nf -ansi-log false \
    -profile jurassic \
    --scatterCount=5 \
    --assayType exome \
    --somatic \
    --workflows="snv,qc,facets,msisensor,mutsig" \
    --aggregate true \
    --mapping $MAPPING \
    --pairing $PAIRING \
    --outDir $ODIR
END_VERSION
