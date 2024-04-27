# MusVar: Output (v1.0.1)

## Introduction

The output consists of the raw output files from the TEMPO pipeline along with some simple post-processing of the mutation tables to filter for non-silent events.


## Directory Structure

```
{outdir}
├── post
│   ├── pipeline_info
│   │   └── version.txt
│   └── reports
│       └── {projectNum}_mutationReport_v1.xlsx
└── tempo
    └── {projectNum}
        ├── bams
        ├── cohort_level
        ├── runlog
        └── somatic
```


## Tempo Output

The core output is from the [Tempo](https://github.com/mskcc/tempo) research pipeline from MSKCC CMO Computational Science group. The raw output from Tempo is in the `tempo` subfolder, and a detailed description of these files can be found here: [//outputs.html](https://deploy-preview-983--cmotempo.netlify.app/outputs.html). _N.B._, to save space, the `bam` and `snp-pileup` files are not delivered by default. If you require them, please contact us.


## Custom Post-processing output

The post folder contains a simple summary mutation report which filters for only non-silent events (this includes `Splice_Site` events). It is also only contains a minimal set of columns that have been renamed for convience. The file is in the `post/reports` folder and is called: `{projectNum}_mutationReport_v1.xlsx`.