#!/bin/bash

yq () {
    egrep $1 $2 | sed 's/.*: //' | tr -d '"' | tr -d "'"
}

OPWD=$PWD
SDIR="$( cd "$( dirname "$0" )" && pwd )"
ADIR=$(realpath $SDIR/..)

. $ADIR/SETENVRC

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
TUMOR=$(cat $PAIRING | transpose.py  | fgrep TUMOR_ID | cut -f2)
NORMAL=$(cat $PAIRING | transpose.py  | fgrep NORMAL_ID | cut -f2)

LOG=${PROJECT_ID}_${TUMOR}_runTempoWES.log

WDIR=$PWD/scratch/$PROJECT_ID/${TUMOR}_${NORMAL}
ODIR=$PWD/out/${PROJECT_ID}/${TUMOR}_${NORMAL}

mkdir -vp $WDIR > $LOG
mkdir -vp $ODIR >> $LOG

WDIR=$(realpath $WDIR)
ODIR=$(realpath $ODIR)

cd $WDIR

nextflow run $ADIR/tempo/dsl2.nf -ansi-log false \
    -profile jurassic \
    --scatterCount=5 \
    --assayType exome \
    --somatic \
    --workflows="snv,qc,facets" \
    --mapping $MAPPING \
    --pairing $PAIRING \
    --outdir $ODIR
    > $LOG
    2> ${LOG/.log/.err}

cat <<-END_VERSION > $ODIR/cmd.sh.log
PWD: $OPWD
SDIR: $SDIR
ADIR: $ADIR
Script: $0 $*

nextflow run $ADIR/tempo/dsl2.nf -ansi-log false \
    -profile jurassic \
    --scatterCount=2 \
    --assayType exome \
    --somatic \
    --workflows="snv,qc,facets" \
    --mapping $MAPPING \
    --pairing $PAIRING \
    --outdir $ODIR

END_VERSION
