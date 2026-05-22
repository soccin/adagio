#!/bin/bash
#SBATCH -J DownSample
#SBATCH -o SLM/downSample.%j.out
#SBATCH --cpus-per-task=6
#SBATCH --time=1-00:00:00
#SBATCH --mem=36G
#SBATCH --partition=cmobic_cpu,cmobic_pipeline

# Downsample a BAM file using Picard DownsampleSam
#
# Example bsub submission (LSF):
#   bsub -o LSF/ -J DN -n 6 -R "rusage[mem=6]" -R cmorsc1 -W 24:00 \
#        scripts/downSampleBam.sh input.bam 0.5

usage() {
    echo "Usage: $(basename $0) <BAM> <P>"
    echo ""
    echo "  BAM  Input BAM file"
    echo "  P    Probability of keeping a read (0.0-1.0)"
    echo ""
    echo "Output: out/<SAMPLE>/<BASENAME>.dn.bam"
    exit 1
}

if [[ $# -lt 2 ]]; then
    usage
fi

BAM=$1
P=$2

if [[ ! -f "$BAM" ]]; then
    echo "Error: BAM file not found: $BAM" >&2
    exit 1
fi

BASE=$(basename ${BAM/.bam/})

# Number of threads: SLURM, LSF, or default to 1
NPROC=${SLURM_CPUS_PER_TASK:-${LSB_DJOB_NUMPROC:-1}}

module load samtools
SM=$(samtools view -H $BAM | egrep "^@RG" | head -1 | tr '\t' '\n' | fgrep SM: | sed 's/SM://')

ODIR=out/$SM
mkdir -p $ODIR

picard DownsampleSam I=$BAM P=$P O=$ODIR/${BASE}.dn.bam

samtools index -@ $NPROC $ODIR/${BASE}.dn.bam

