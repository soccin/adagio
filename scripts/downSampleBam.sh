#!/bin/bash

#bsub -o LSF/ -J DN -n 6 -R "rusage[mem=6]" -R cmorsc1 -W 24:00 \

BAM=$1
P=$2

BASE=$(basename ${BAM/.bam/})
module load samtools
SM=$(samtools view -H $BAM | egrep "^@RG" | head -1 | tr '\t' '\n' | fgrep SM: | sed 's/SM://')

ODIR=out/$SM
mkdir -p $ODIR

picardV2 DownsampleSam I=$BAM P=$P O=$ODIR/${BASE}.dn.bam

samtools index -@ $LSB_DJOB_NUMPROC $ODIR/${BASE}.dn.bam

