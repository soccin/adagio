#!/bin/bash

set -eu
SDIR="$( cd "$( dirname "$0" )" && pwd )"
RDIR=$(realpath $SDIR/..)

mkdir -p post/pipeline_info

cp out/*/pipeline_info/*html post/pipeline_info
cp out/*/pipeline_info/*txt post/pipeline_info
cp out/*/pipeline_info/*pdf post/pipeline_info

ASSAY=$(cat out/*/runlog/cmd.sh.log | fgrep ASSAY_TYPE | awk '{print $2}')

echo "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-="
echo Rscript $RDIR/scripts/report01.R $ASSAY
echo
Rscript $RDIR/scripts/report01.R $ASSAY

echo "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-="
echo Rscript $RDIR/scripts/qcReport01.R
echo
Rscript $RDIR/scripts/qcReport01.R

if [ "$ASSAY" == "genome" ]; then
  echo "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-="
  echo Rscript $RDIR/scripts/reportSV01.R
  echo
  Rscript $RDIR/scripts/reportSV01.R
fi

mkdir -p post/plots/facets
cp $(find out -name '*purity.CNCF.png') post/plots/facets

echo "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-="
echo Rscript $RDIR/scripts/reportFacets01.R
echo
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
