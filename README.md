# ADAGIO

A genomic sequencing pipeline framework - a customized derivation of [_Tempo_](https://github.com/mskcc/tempo) for processing paired-end WES/WGS human cancer samples with matched normal controls.

Some nice [adagios](https://open.spotify.com/playlist/3o1pG5q6H3FadR6zmeNBTo?si=48d2b7228a754dc0).

## Version: v2.4.0

### Summary

**v2.4.0** represents a significant modernization of the Adagio pipeline with major architectural improvements:

- **Tempo Submodule Modernization**: Updated to devs branch (a37c341b) featuring nf-core framework integration and Apache Spark optimization for enhanced MarkDuplicates processing
- **Enhanced FACETS Reporting**: Complete refactoring with multi-sheet Excel export, improved QC processing, and tidyverse compliance
- **Consolidated Documentation**: Unified changelog system with dedicated tempo submodule tracking

### Improvements

- **Performance**: Apache Spark-based MarkDuplicates with parallel processing optimizations
- **Reporting**: Multi-sheet Excel exports with comprehensive analysis results (runInfo, armLevel, geneLevel)
- **Code Quality**: Tidyverse-compliant R scripts with enhanced documentation and error handling
- **Framework**: Full nf-core standard adoption with improved development workflow



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

