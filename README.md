# ADAGIO

A derivation of [_Tempo_](https://github.com/mskcc/tempo).

Some nice [adagios](https://open.spotify.com/playlist/3o1pG5q6H3FadR6zmeNBTo?si=48d2b7228a754dc0).

## Version: v2.3.3 - master

**Iris** cluster version. Currently tracking the eos-devs branch of tempo (0f8d1ce5) forked from mskcc/tempo develop (e136e568)

### Tempo advancements

- **Pipeline Updates**: Updated tempo submodule with updates for:
  - updates to delly and svaba
  - optimizations for neoantigen

- **Workflow conditional changes**: Turned off the following modules for WGS runs
  - LoH/RunLOHHLA.nf
  - QC/SomaticRunMultiQC.nf

- **Neoantigen Analysis**: Added resource allocation for RunNeoantigen process in both WES and WGS configurations

### General Improvements

- **New SV Reporting System**: Added comprehensive structural variant reporting with BEDPE file processing and Excel output generation

- **Enhanced Report Organization**: Improved file naming (SNV_Report01) and dynamic file handling for better workflow management

- **Assay-Specific Reporting**: Implemented conditional report generation that adapts content based on analysis type (WES vs WGS)

- **Workflow Configuration**: Refactored WGS workflow parameters for improved maintainability and consistency



## Docs

Online docs at DEVELOP: (https://deploy-preview-983--cmotempo.netlify.app) or 
MASTER: (https://cmotempo.netlify.app/).

## Install

- Make sure to clone with `--recurse-submodules`.

- See `docs/installation.md` for more info. Specifically need to install nextflow in `bin`.

## Resume

To resume a run use the following script template:

```
#!/bin/bash

export NXF_SINGULARITY_CACHEDIR=/rtsess01/compute/juno/bic/ROOT/opt/singularity/cachedir_socci
export TMPDIR=/scratch/socci
export PATH=$PROJECT_ROOT/adagio/bin:$PATH

nextflow run $PROJECT_ROOT/adagio/tempo/dsl2.nf -resume \
# args from .nextflow/history
```

(sample version of this in `/scripts` folder). Remember you need to delete/move the `trace.txt`, `*.html`, and `*.tsv` files. Do

```
mkdir passN
mv trace.txt *.html *.tsv passN
```

