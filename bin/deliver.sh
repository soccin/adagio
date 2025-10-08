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

BIC_DELIVERY=/rtsess01/juno/home/socci/Code/BIC/Delivery/Version2j
Rscript $BIC_DELIVERY/readme2yaml.R tempo
python3 $BIC_DELIVERY/authorization_db/init_impact_project_permissions.py -p project.yaml

eval $(cat out/*/runlog/cmd.sh.log  | fgrep PROJECT_ID | sed 's/: /=/')

echo
echo "========================================================================="
echo
sed "s/{PROJNO}/$PROJECT_ID/g" \
  $RDIR/assets/delivery_email_template.txt \
  | tee deliveryEmail_${PROJECT_ID}_$(date +%y%m%d).txt

