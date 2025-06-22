# ADAGIO

A derivation of [_Tempo_](https://github.com/mskcc/tempo).

Some nice [adagios](https://open.spotify.com/playlist/3o1pG5q6H3FadR6zmeNBTo?si=48d2b7228a754dc0).

## Branch: proj/05469 (devs/tempo-fmap)

Experimental test of WGS-BAM pipeline on 05469. Improved Delly and SVaba

Uses new tempo with faster mapping and several other improvements (2829e604)

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

