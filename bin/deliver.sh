#!/bin/bash

if [ "$#" != "1" ]; then
    echo -e "\n   usage: deliver.sh /path/to/delivery/folder/r_00x\n"
    exit
fi

ODIR=$1
mkdir -p $ODIR/tempo

rsync -rvP --exclude="*.ba[mi]" --exclude="*.snp_pileup.gz" out/ $ODIR/tempo
rsync -rvP post $ODIR


