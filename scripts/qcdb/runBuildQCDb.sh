#!/bin/bash
#SBATCH -J QCDb-build
#SBATCH -o SLM/qcdbBuild.%j.out
#SBATCH -c 8
#SBATCH --mem=96G
#SBATCH -t 2:00:00
#SBATCH --partition cpushort,cmobic_short

usage() {
    cat <<EOF

Usage: sbatch runBuildQCDb.sh [buildQCDb.R options]

Build the QC background database from a finished adagio run. Submit
from the project folder (the one that holds out/). All options are
passed to buildQCDb.R; see "Rscript buildQCDb.R --help".

Use the ~/bin/sbatch wrapper, or pass
--export=ALL,SBATCH_SCRIPT_DIR=<adagio>/scripts/qcdb, so the job can find
buildQCDb.R.

Example:
  sbatch runBuildQCDb.sh --pairing=inputTempo_pairing.tsv \\
      --lims=inputs/TN_pairs_200_samples.csv

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

if [ ! -e "$SDIR/buildQCDb.R" ]; then
    echo -e "\n   Cannot find buildQCDb.R in $SDIR; set SBATCH_SCRIPT_DIR\n"
    exit 1
fi

# Node-local temp space, never the node's /tmp
JOBTMP=/localscratch/$USER/qcdb/${SLURM_JOB_ID:-$$}
mkdir -p "$JOBTMP"
export TMPDIR="$JOBTMP"
trap 'rm -rf "$JOBTMP"' EXIT

Rscript "$SDIR/buildQCDb.R" --cores="${SLURM_CPUS_PER_TASK:-1}" "$@"
