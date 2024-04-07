#!/bin/bash

export NXF_SINGULARITY_CACHEDIR=/rtsess01/compute/juno/bic/ROOT/opt/singularity/cachedir_socci
export TMPDIR=/scratch/socci
export PATH=$PROJECT_ROOT/adagio/bin:$PATH

nextflow run $PROJECT_ROOT/adagio/tempo/dsl2.nf -resume \
# args from .nextflow/history
