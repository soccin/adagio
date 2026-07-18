#!/bin/bash

SDIR="$( cd "$( dirname "$0" )" && pwd )"
RDIR=$(realpath $SDIR/..)

if [ "$#" != "1" ]; then
    echo -e "\n   usage: deliver.sh /path/to/delivery/folder/r_00x\n"
    exit
fi

ODIR=$1
mkdir -p $ODIR/tempo

rsync -rvP --exclude="*.ba[mi]" --exclude="*.snp_pileup.gz" --exclude="*germline*" out/ $ODIR/tempo
rsync -rvP post $ODIR

eval $(cat out/*/runlog/cmd.sh.log  | fgrep PROJECT_ID | sed 's/: /=/')

if [ -e "Map/sbam" ]; then
  mkdir $ODIR/mapping
  rsync -rvP --exclude="*.ba[mi]" Map/sbam/ $ODIR/mapping
fi

if [ -e "Map/out/metrics" ]; then
  mkdir -p $ODIR/mapping
  rsync -rvP Map/out/metrics $ODIR/mapping
fi

echo
echo "========================================================================="
echo
sed "s/{PROJNO}/$PROJECT_ID/g" \
  $RDIR/assets/delivery_email_template.txt \
  | tee deliveryEmail_${PROJECT_ID}_$(date +%y%m%d).txt

CLUSTER=$(getCluster.sh)
if [ "$CLUSTER" != "IRIS" ]; then
  BIC_DELIVERY=$HOME/Code/BIC/Delivery/Version2j
  Rscript $BIC_DELIVERY/readme2yaml.R adagio

  module purge
  module load python/3.8.0
  module load py-python-ldap/3.4.2
  python3 $BIC_DELIVERY/authorization_db/init_impact_project_permissions.py -p project.yaml
fi
