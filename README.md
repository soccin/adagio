# ADAGIO

A derivation of [_Tempo_](https://github.com/mskcc/tempo).

Some nice [adagios](https://open.spotify.com/playlist/3o1pG5q6H3FadR6zmeNBTo?si=48d2b7228a754dc0).

## Version: v1.5.0 (2025-06-22)

See change log for all changes from v1.0.4 (2024-10-30:ffa846e)

Currently using develop version of tempo forked from commit:4400235d (origin/develop)

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

