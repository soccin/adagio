#!/bin/bash

set -eu
SDIR="$( cd "$( dirname "$0" )" && pwd )"
RDIR=$(realpath $SDIR/..)

mkdir -p post/pipeline_info

#
# 
REPORT_HTML=$(find -L . | fgrep /report.html | head -1)

cp $REPORT_HTML post/pipeline_info
cp $(ls -rt $(dirname $REPORT_HTML)/timeline.html | tail -1) post/pipeline_info
cp $(ls -rt $(dirname $REPORT_HTML)/*trace* | tail -1) post/pipeline_info

ASSAY=$(cat out/*/runlog/cmd.sh.log | fgrep ASSAY_TYPE | awk '{print $2}')

Rscript $RDIR/scripts/report01.R $ASSAY

if [ "$ASSAY" == "genome" ]; then
  Rscript $RDIR/scripts/reportSV01.R
fi

mkdir -p post/plots/facets
cp $(find out -name '*purity.CNCF.png') post/plots/facets

Rscript $RDIR/scripts/reportFacets01.R

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
ASSAY: $ASSAY
END_VERSION


