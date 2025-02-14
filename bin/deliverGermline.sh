#!/bin/bash

if [ "$#" != "1" ]; then
    echo -e "\n   usage: deliver.sh /path/to/delivery/folder/r_00x\n"
    exit
fi

ODIR=$1
mkdir -p $ODIR/tempo-germline
mkdir -p $ODIR/post/germlime

rsync -avP  out/*/germline $ODIR/tempo-germline
cp post/reports/* $ODIR/post/germlime


