#!/bin/bash

set -eu
SDIR="$( cd "$( dirname "$0" )" && pwd )"
RDIR=$(realpath $SDIR/..)

mkdir -p post/pipeline_info
cp $(ls -rt run/*/*/report.html | tail -1) post/pipeline_info
cp $(ls -rt run/*/*/timeline.html | tail -1) post/pipeline_info

Rscript $RDIR/scripts/report01.R

mkdir -p post/plots/facets
cp $(find out -name '*purity.CNCF.png') post/plots/facets

CMD_LOG=post/pipeline_info/version.txt

GTAG=$(git --git-dir=$RDIR/.git --work-tree=$RDIR describe --long --tags --dirty="-UNCOMMITED" --always)
GURL=$(git --git-dir=$RDIR/.git --work-tree=$RDIR config --get remote.origin.url)

cp out/*/runlog/cmd.sh.log post/pipeline_info

cat <<-END_VERSION > $CMD_LOG
DATE: $(date)
SDIR: $RDIR
GURL: $GURL
GTAG: $GTAG
END_VERSION


