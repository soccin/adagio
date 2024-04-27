#!/bin/bash

set -eu
SDIR="$( cd "$( dirname "$0" )" && pwd )"


mkdir -p post/pipeline_info
cp $(ls -rt run/*/*/report.html | tail -1) post/pipeline_info
cp $(ls -rt run/*/*/timeline.html | tail -1) post/pipeline_info

Rscript $SDIR/scripts/filter01.R

CMD_LOG=post/pipeline_info/version.txt

GTAG=$(git --git-dir=$SDIR/.git --work-tree=$SDIR describe --all --long --tags --dirty="-UNCOMMITED" --always)
GURL=$(git --git-dir=$SDIR/.git --work-tree=$SDIR config --get remote.origin.url)

cat <<-END_VERSION > $CMD_LOG
DATE: $(date)
SDIR: $SDIR
GURL: $GURL
GTAG: $GTAG
END_VERSION

cp out/*/runlog/cmd.sh.log post/pipeline_info

