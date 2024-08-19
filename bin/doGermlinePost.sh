#!/bin/bash

SDIR=$(dirname "$(readlink -f "$0")")

mkdir -p tmp/germline
for file in $(find out -name "*.vcf.gz" | fgrep union.pass); do
    echo $file
    zcat $file > tmp/germline/$(basename ${file/.gz/})
done

for file in tmp/germline/*.vcf; do
    echo $file;
    sid=$(basename $file | sed 's/.union.*//')
    bsub -o LSF/ -J VCF2MAF_$$ -n 15 -R cmorsc1 \
        /home/socci/Work/Users/LoweS/HoY/COMPASS/vcf2MafApp/vcf2maf.sh \
            GRCh37 \
            $file $sid $sid
done

bSync VCF2MAF_$$

Rscript $SDIR/../scripts/reportGerm01.R tmp/germline/*maf

