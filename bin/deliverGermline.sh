#!/bin/bash

if [ "$#" != "1" ]; then
    echo -e "\n   usage: deliver.sh /path/to/delivery/folder/r_00x\n"
    exit
fi

ODIR=$1

# All writes to the delivery area run as the service account
BOT_USER=svc_core001_bot01
asbot() {
    dzdo -u "$BOT_USER" "$@"
}

# Every delivered file and folder gets this group, and macOS metadata
# files ("._<name>") are not delivered; see deliver.sh
DGROUP=grp_hpc_core001

asbot rsync -avP --chown=:"$DGROUP" --exclude="._*" out/*/germline $ODIR/tempo-germline
asbot rsync -avP --chown=:"$DGROUP" --exclude="._*" germline/* $ODIR/tempo-germline/post

BIC_DELIVERY=$HOME/Code/BIC/Delivery/Version2j
Rscript $BIC_DELIVERY/readme2yaml.R adagio

module purge
module load python/3.8.0
module load py-python-ldap/3.4.2
python3 $BIC_DELIVERY/authorization_db/init_impact_project_permissions.py -p project.yaml

