#!/bin/bash
#SBATCH -J QCDb-targetGC
#SBATCH -o SLM/qcdbTargetGC.%j.out
#SBATCH -c 2
#SBATCH --mem=16G
#SBATCH -t 1:00:00
#SBATCH --partition cpushort,cmobic_short

usage() {
    cat <<EOF

Usage: sbatch runMakeTargetGC.sh [makeTargetGC.R options]

Build the per-target GC table of the QC background database. All
options are passed to makeTargetGC.R; see "Rscript makeTargetGC.R --help".

Use the ~/bin/sbatch wrapper, or pass
--export=ALL,SBATCH_SCRIPT_DIR=<adagio>/scripts/qcdb, so the job can find
makeTargetGC.R.

EOF
}

for arg in "$@"; do
    if [ "$arg" == "-h" ] || [ "$arg" == "--help" ]; then
        usage
        exit 0
    fi
done

# Vanilla sbatch runs a spooled copy of the script; see bin/runTempoWESCohort.sh
if [ -n "$SBATCH_SCRIPT_DIR" ]; then
    SDIR="$SBATCH_SCRIPT_DIR"
else
    SDIR="$( cd "$( dirname "$0" )" && pwd )"
fi

if [ ! -e "$SDIR/makeTargetGC.R" ]; then
    echo -e "\n   Cannot find makeTargetGC.R in $SDIR; set SBATCH_SCRIPT_DIR\n"
    exit 1
fi

# Node-local temp space, never the node's /tmp
JOBTMP=/localscratch/$USER/qcdb/${SLURM_JOB_ID:-$$}
mkdir -p "$JOBTMP"
export TMPDIR="$JOBTMP"
trap 'rm -rf "$JOBTMP"' EXIT

Rscript "$SDIR/makeTargetGC.R" "$@"
