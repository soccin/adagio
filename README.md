# ADAGIO

A derivation of [_Tempo_](https://github.com/mskcc/tempo).

Some nice [adagios](https://open.spotify.com/playlist/3o1pG5q6H3FadR6zmeNBTo?si=48d2b7228a754dc0).

## Version: v2.3.7 - master

**Iris** cluster version. Currently tracking the eos-devs branch of tempo (0f8d1ce5) forked from mskcc/tempo develop (e136e568)

### Latest Release (v2.3.7)

- **Bug Fixes**: Disabled scratch temp directory usage and simplified project extraction in reportSV01.R
- **Cluster Detection**: Added utility function and modernized detection logic across reporting scripts
- **Script Improvements**: Enhanced getClusterName.sh with better error handling and modular design

### Previous Release (v2.3.5)

- **FACETS Post-processing**: Added automated FACETS report generation in `doPost.sh` with filtered segmentation files and comprehensive Excel output
- **Report Organization**: FACETS reports now output to `post/reports/` directory with versioned filenames (v3)

### Previous Release (v2.3.4)

- **Germline SV Reporting**: Added `scripts/reportGermSV01.R` for comprehensive germline structural variant analysis
- **Directory Restructure**: Refactored germline post-processing - output moved from `post/` to `germline/` directory
- **Resource Optimization**: Enhanced CPU and memory allocation for Delly, SvABA, Neoantigen, and MultiQC processes
- **Enhanced QC**: Improved QC reporting with additional metrics, sample type grouping, and better visualizations
- **Workflow Improvements**: Configurable target validation and better error handling in sample processing
- **Delivery Process**: Optimized file delivery with germline exclusions for cleaner output separation

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

