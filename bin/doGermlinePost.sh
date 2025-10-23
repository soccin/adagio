#!/bin/bash

#
#  Version 2
#

SDIR=$(dirname "$(readlink -f "$0")")
RDIR=$(realpath $SDIR/..)

mkdir -p germline/pipeline_info

cp out/*/pipeline_info/*html germline/pipeline_info
cp out/*/pipeline_info/*txt germline/pipeline_info
cp out/*/pipeline_info/*pdf germline/pipeline_info

Rscript $SDIR/../scripts/reportGerm01.R

ASSAY=$(cat out/*/runlog/cmd.sh.log | fgrep ASSAY_TYPE | awk '{print $2}')
if [ "$ASSAY" == "genome" ]; then
  Rscript $SDIR/../scripts/reportGermSV01.R
fi

CMD_LOG=germline/pipeline_info/version.txt

GTAG=$(git --git-dir=$RDIR/.git --work-tree=$RDIR describe --long --tags --dirty="-UNCOMMITED" --always)
GURL=$(git --git-dir=$RDIR/.git --work-tree=$RDIR config --get remote.origin.url)

cp out/*/runlog/cmd.sh.log germline/pipeline_info
cp $RDIR/docs/output.html germline/pipeline_info

cat <<-END_VERSION > $CMD_LOG
DATE: $(date)
SDIR: $RDIR
GURL: $GURL
GTAG: $GTAG
END_VERSION
