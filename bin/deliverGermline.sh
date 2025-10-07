#!/bin/bash

if [ "$#" != "1" ]; then
    echo -e "\n   usage: deliver.sh /path/to/delivery/folder/r_00x\n"
    exit
fi

ODIR=$1

rsync -avP  out/*/germline $ODIR/tempo-germline
rsync -avP germline/* $ODIR/tempo-germline/post


