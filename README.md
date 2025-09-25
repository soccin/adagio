# ADAGIO

A derivation of [_Tempo_](https://github.com/mskcc/tempo).

Some nice [adagios](https://open.spotify.com/playlist/3o1pG5q6H3FadR6zmeNBTo?si=48d2b7228a754dc0).

## Version: v2.4.2 - master

**Neo/Juno** cluster version with nf-core integration. Currently tracking tempo submodule (00eb724b) with comprehensive nf-core/markdup_spark integration and Spark-based processing improvements.

### Latest Release (v2.4.2)

- **nf-core Integration**: Complete integration with nf-core framework and tools in tempo submodule
- **MarkDuplicates Enhancement**: Migration to Spark-based MarkDuplicates with SETNMMDANDUQTAGS processing
- **Cluster Configuration**: Added cluster-specific pipeline configurations for IRIS and JUNO clusters
- **Resource Optimization**: Enhanced CPU allocation (minimum 2 CPUs per process) and improved resource management
- **BQSR Improvements**: Added scatter-based BQSR processing for better parallelization
- **Documentation**: Consolidated changelog documentation and created comprehensive tempo submodule history

### Previous Release (v2.3.8)

- **Port Attempt**: Second attempt to port back to neo/juno infrastructure
- **Branch Merge**: Integrated devs/neo-redo-b branch with cluster-specific improvements
- **Configuration Updates**: Enhanced cluster detection and resource allocation

### Previous Release (v2.3.7)

- **Bug Fixes**: Disabled scratch temp directory usage and simplified project extraction in reportSV01.R
- **Cluster Detection**: Added utility function and modernized detection logic across reporting scripts
- **Script Improvements**: Enhanced getClusterName.sh with better error handling and modular design

### Tempo Submodule Advancements

- **nf-core Framework**: Full adoption of nf-core framework with template compliance
- **Spark Processing**: Enhanced processing with Spark-based MarkDuplicates and parallel SETNMMDANDUQTAGS
- **Module Integration**: Local module customizations with upstream compatibility
- **Performance**: Parallelized processing with interval splitting and improved resource utilization
- **Documentation**: Enhanced README and comprehensive integration status documentation

### Configuration Improvements

- **Cluster-Specific Configs**: Separate configurations for IRIS (`tempo-wes-iris`) and JUNO (`tempo-wes-juno`) clusters
- **Resource Allocation**: Optimized CPU and memory settings for different cluster environments
- **Pipeline Parameters**: Enhanced parameter management with cluster-specific overrides
- **Error Handling**: Improved error detection and temporary workarounds for IRIS configuration issues

### General Improvements

- **Enhanced FACETS Reporting**: Multi-sheet Excel export with comprehensive analysis results (runInfo, armLevel, geneLevel)
- **Quality Control**: Individual QC file processing with comprehensive failed sample filtering
- **Code Quality**: Tidyverse compliance, improved documentation, and better code organization
- **File Processing**: Robust pattern matching, error handling, and progress reporting



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

