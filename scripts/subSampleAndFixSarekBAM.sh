#!/bin/bash

BAM=$1
BASE=$(basename $BAM)
P=$2

module load samtools

SM=$(samtools view -H $BAM | egrep "^@RG" | head -1 | tr '\t' '\n' | fgrep SM: | sed 's/SM://')
NEW_RG=$(samtools view -H $BAM | egrep "^@RG" | head -1 | perl -pe 's/ID:\S+/ID:1/;s/\t/\\t/g')

ODIR=res/$SM
mkdir -p $ODIR

if [ "$P" == "1" ]; then
    SARG=""
else
    SARG="-s $P"
fi

(
    samtools view -H $BAM | egrep "^@(HD|SQ)";
    samtools view -@ 12 $SARG $BAM
) \
    | samtools addreplacerg -r $NEW_RG -@ 2 -o $ODIR/${BASE/.bam/.sub.nrg.bam} -

samtools index $ODIR/${BASE/.bam/.sub.nrg.bam}
