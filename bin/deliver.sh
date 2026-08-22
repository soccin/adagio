#!/bin/bash

SDIR="$( cd "$( dirname "$0" )" && pwd )"
RDIR=$(realpath $SDIR/..)

# Default delivery path from .../Users/Aa/BBB/Proj_nnnnn/...
# -> aaa/bbb/Proj_nnnnn (first two folders lowercased; project as-is)
CWD=$(pwd)
if [[ "$CWD" != *"/Users/"* ]]; then
    DPATH=""
else
    rest="${CWD#*/Users/}"
    IFS=/ read -r u1 u2 proj _ <<< "$rest"
    if [[ -n "$u1" && -n "$u2" && -n "$proj" ]]; then
        DPATH="$(printf '%s' "$u1" | tr '[:upper:]' '[:lower:]')/$(printf '%s' "$u2" | tr '[:upper:]' '[:lower:]')/$proj"
    else
        DPATH=""
    fi
fi

usage() {
    echo -e "\n   usage: deliver.sh /path/to/delivery/folder/r_00x"
    echo -e "          deliver.sh -d|--default"
    echo -e "\n   default: ${DPATH:-"(none)"}\n"
}

ODIR=""
USE_DEFAULT=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--default)
            USE_DEFAULT=1
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            ODIR="$1"
            shift
            ;;
    esac
done

BDSERVER=isvzeta
BDSERVER=pyr
DROOT=/ifs/rtsia01/bic/results

if [[ "$USE_DEFAULT" -eq 1 && -z "$ODIR" ]]; then
    if [[ -z "$DPATH" ]]; then
        echo "Error: no default delivery path for current directory"
        usage
        exit 1
    fi
    ODIR="$DROOT/$DPATH"
fi

if [[ -z "$ODIR" ]]; then
    usage
    exit
fi

# CURRDIR: trailing /r_NNN on ARG1 as-is; else next after latest on BDSERVER; else r_001
CURRDIR=r_001
if [[ "$ODIR" =~ /r_[0-9]+$ ]]; then
    CURRDIR="${ODIR##*/}"
    ODIR="${ODIR%/*}"
else
    echo "Probing $BDSERVER for existing delivery folders under $ODIR ..."
    if ssh "$BDSERVER" "test -d '$ODIR'"; then
        last=$(ssh "$BDSERVER" "ls -1 '$ODIR' | grep -E '^r_[0-9]+\$' | sort | tail -1")
        if [[ "$last" =~ ^r_([0-9]+)$ ]]; then
            CURRDIR=$(printf 'r_%03d' $((10#${BASH_REMATCH[1]} + 1)))
        fi
    fi
    echo "Probe complete."
fi

echo "ODIR=$ODIR"
echo "CURRDIR=$CURRDIR"

echo "Making $ODIR/$CURRDIR/tempo on $BDSERVER ..."
ssh $BDSERVER mkdir -p $ODIR/$CURRDIR/tempo

rsync -rvP --exclude="*.ba[mi]" --exclude="*.snp_pileup.gz" --exclude="*germline*" out/ ${BDSERVER}:$ODIR/$CURRDIR/tempo
rsync -rvP post ${BDSERVER}:$ODIR/$CURRDIR

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
  . $BIC_DELIVERY/venv/bin/activate
  python3 $BIC_DELIVERY/authorization_db/init_impact_project_permissions.py -p project.yaml
fi
