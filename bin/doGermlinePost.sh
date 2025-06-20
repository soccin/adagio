#!/bin/bash

#
#  Version 2
#

SDIR=$(dirname "$(readlink -f "$0")")
RDIR=$(realpath $SDIR/..)

mkdir -p post/pipeline_info
cp $(ls -rt run/*/*/report.html | tail -1) post/pipeline_info
cp $(ls -rt run/*/*/timeline.html | tail -1) post/pipeline_info

Rscript $SDIR/../scripts/reportGerm01.R
CMD_LOG=post/pipeline_info/version.txt

GTAG=$(git --git-dir=$RDIR/.git --work-tree=$RDIR describe --long --tags --dirty="-UNCOMMITED" --always)
GURL=$(git --git-dir=$RDIR/.git --work-tree=$RDIR config --get remote.origin.url)

cp out/*/runlog/cmd.sh.log post/pipeline_info
cp $RDIR/docs/output.html post/pipeline_info

cat <<-END_VERSION > $CMD_LOG
DATE: $(date)
SDIR: $RDIR
GURL: $GURL
GTAG: $GTAG
END_VERSION
