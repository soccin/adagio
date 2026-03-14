#!/bin/bash

if [ "$#" != "1" ]; then
    echo -e "\n   usage: deliver.sh /path/to/delivery/folder/r_00x\n"
    exit
fi

ODIR=$1

rsync -avP  out/*/germline $ODIR/tempo-germline
rsync -avP germline/* $ODIR/tempo-germline/post

BIC_DELIVERY=$HOME/Code/BIC/Delivery/Version2j
Rscript $BIC_DELIVERY/readme2yaml.R adagio

module purge
module load python/3.8.0
module load py-python-ldap/3.4.2
python3 $BIC_DELIVERY/authorization_db/init_impact_project_permissions.py -p project.yaml

