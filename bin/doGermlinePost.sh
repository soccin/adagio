#!/bin/bash

#
#  Version 2
#

SDIR=$(dirname "$(readlink -f "$0")")
RDIR=$(realpath $SDIR/..)

mkdir -p germline/pipeline_info
cp $(ls -rt run/report.html | tail -1) germline/pipeline_info
cp $(ls -rt run/timeline.html | tail -1) germline/pipeline_info

Rscript $SDIR/../scripts/reportGerm01.R
Rscript $SDIR/../scripts/reportGermSV01.R
CMD_LOG=germline/pipeline_info/version.txt

exit

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
