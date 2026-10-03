# BIC Variant Pipeline (v3.2.2)

## Introduction

The results have two parts. The `tempo` folder holds the output of the
Tempo pipeline as it was produced. The `post` folder holds reports we
build from the Tempo output: a mutation table filtered to protein-changing
mutations, copy number summaries, and QC reports.

In the names below, `<no>` is the project number (for example `16083_I`)
and `<sample>` is a sample ID. Reports marked WGS are made only for
whole-genome projects; the others are made for exome and genome projects.

## Directory Structure

```
<delivery folder>
├── post
│   ├── reports
│   │   ├── Proj_<no>_SNV_Report01_v4.xlsx
│   │   ├── Proj_<no>_facets_v5.xlsx
│   │   ├── Proj_<no>_facetsQCRpt_v1.xlsx
│   │   ├── Proj_<no>_qcRpt01.pdf
│   │   ├── Proj_<no>_SV_Report01_v8.xlsx         (WGS)
│   │   ├── Proj_<no>_All_Report01_v2.xlsx        (WGS)
│   │   ├── DESCRIPTION_ALL_REPORT.md             (WGS)
│   │   ├── Proj_<no>_WGSStats_v1.xlsx            (WGS)
│   │   └── Proj_<no>_WGSStats_v1.pdf             (WGS)
│   ├── plots
│   │   └── facets
│   │       ├── <sample>__<normal>_purity.CNCF.png
│   │       ├── Proj_<no>_Filtered_facets_hisens.seg
│   │       └── Proj_<no>_Filtered_facets_purity.seg
│   └── pipeline_info
│       ├── version.txt
│       ├── cmd.sh.log
│       ├── output.html
│       ├── execution_report_<date>.html
│       ├── execution_timeline_<date>.html
│       └── execution_trace_<date>.txt
└── tempo
    └── <no>
        ├── bams
        ├── cohort_level
        ├── pipeline_info
        ├── runlog
        └── somatic
```

## Tempo Output

The core analysis is done by [Tempo](https://github.com/mskcc/tempo), a
pipeline from the MSKCC CMO Computational Sciences group. The `tempo`
folder holds its output as it was produced. The Tempo documentation
describes these files:
[Tempo README](https://github.com/mskcc/tempo/blob/develop/README.md).

- `bams`: per-sample QC (fastp, Alfred, Qualimap, CollectHsMetrics for
  exomes, MultiQC). The BAM files are not delivered.
- `somatic`: per tumor/normal pair results: mutation calls (VCF and MAF),
  FACETS copy number, Conpair concordance and contamination, and for WGS
  structural variants and mutational signatures.
- `cohort_level`: the same results merged across all pairs, for example
  `mut_somatic.maf` and `sample_data.txt`.
- `pipeline_info`, `runlog`: Nextflow run reports and the run command.

To save space, the BAM and snp-pileup files are not delivered. If you
need them, please contact us.

## Post Folder

### SNV Report (`Proj_<no>_SNV_Report01_v4.xlsx`)

Somatic mutations from Tempo's filtered cohort MAF (`mut_somatic.maf`).

**Sample Data.** One row per tumor:

- `SampleID`, `NormalID`: tumor and matched normal.
- `Mutation Count`: all somatic mutations that passed Tempo's filters,
  silent and non-coding included.
- `TMB`: tumor mutational burden from Tempo (mutations per Mb). Exome
  projects only.
- `Facets Purity`, `Facets Ploidy`, `Fraction Genome Altered`: FACETS
  estimates.
- `facets_qc`, `dipLogR`: FACETS QC flag and baseline log ratio.
- `NonSyn Mutation Count`: mutations in the Mutations sheet, not counting
  the TERT promoter mutations added back (see below).

A sample passes the FACETS check if `facets_qc` is TRUE or
`|dipLogR| < 0.5`. For samples that do not pass, `Facets Ploidy` and
`Fraction Genome Altered` are left blank because the fit is not
reliable. Purity is always shown.

**Gene Stats.** Genes mutated in 2 or more samples. `Count` is the number
of samples with a mutation in the gene, `Freq` is `Count` divided by the
number of samples with at least one mutation in the Mutations sheet, and
`Samples` lists them. This sheet is present only when more than one
sample has mutations.

**Mutations.** One row per mutation that changes the protein: those with
a protein change (`HGVSp_Short`) that is not synonymous. This keeps
missense, nonsense, frameshift, in-frame indel and splice site mutations
and drops silent, intronic, UTR and intergenic ones. TERT promoter
mutations are the exception: they are always kept. Tempo's filters (for
example the repeat filter) often remove them, so the report adds back
TERT promoter calls that Tempo filtered out. Columns:

- `Sample`, `Gene`, `Type` (variant class), `dbSNP_RS`, `Alteration`
  (protein change).
- `oncogenic`: OncoKB annotation.
- `VAF`, `t_depth`, `t_alt_count`: tumor allele frequency, depth and alt
  read count.
- `n_depth`, `n_alt_count`, `Normal_Sample`: the same for the normal.
- `GPos`, `REF`, `ALT`: genomic position (GRCh37) and alleles.
- `non_cancer_AF_popmax`: gnomAD non-cancer population maximum allele
  frequency.
- `SIFT`, `PolyPhen`, `VEP_IMPACT`: VEP predictions.
- `MSKWES_GENE_Frac`: fraction of samples in the MSK WES cohort on
  cBioPortal (2024-08-09) with a mutation in the gene.

### FACETS Report (`Proj_<no>_facets_v5.xlsx`)

Copy number results from FACETS. Samples that do not pass the FACETS
check (above) are left out of the `armLevel` and `geneLevelFocal` sheets
and the `.seg` files.

- `runInfo`: purity, ploidy, dipLogR and other fit results for every
  tumor.
- `armLevel`: copy number state of each autosomal chromosome arm.
- `geneLevelFocal`: genes on a focal copy number change (segment 1 Mb or
  shorter) in at least one tumor, with the percentage of tumors with a
  loss, gain or copy-neutral LOH at the gene.
- `facetsQC`: the FACETS QC metrics and flags for every tumor.
- `facetsParams`: the FACETS version and parameters.

### FACETS QC Report (`Proj_<no>_facetsQCRpt_v1.xlsx`)

One row per tumor: purity, ploidy, dipLogR, whole genome doubling,
fraction of the genome altered, counts of amplifications and homozygous
deletions, number of segments, the overall `facets_qc` flag, and
`FailedFilters`, the names of the QC checks the sample failed.

### QC Report (`Proj_<no>_qcRpt01.pdf`)

Plots of Conpair tumor/normal concordance and contamination for each pair.
For exomes, it also plots target coverage from CollectHsMetrics (mean
target coverage, fraction of targets with zero coverage, fraction of
target bases at 20x and 100x), with caution and fail lines.

### WGS Reports

- `Proj_<no>_SV_Report01_v8.xlsx`: somatic structural variants, with
  per-sample counts (`SampleData`), recurrent gene pairs (`SVFreq`), all
  calls (`SVEvents`), and a description of every column
  (`ColDescriptions`).
- `Proj_<no>_All_Report01_v2.xlsx`: SVs, mutations and focal copy number
  changes combined by sample and by gene. `DESCRIPTION_ALL_REPORT.md`
  explains it.
- `Proj_<no>_WGSStats_v1.xlsx` and `.pdf`: whole-genome coverage and
  alignment statistics for each sample.

### Plots and Segmentation Files (`plots/facets`)

- `<sample>__<normal>_purity.CNCF.png`: FACETS copy number profile for
  each tumor.
- `Proj_<no>_Filtered_facets_hisens.seg`,
  `Proj_<no>_Filtered_facets_purity.seg`: FACETS segments from the
  high-sensitivity and purity fits, for samples that pass the FACETS
  check. These are tab-delimited and can be loaded into IGV.

### Pipeline Info

- `version.txt`: date, pipeline code location and version, and assay type.
- `cmd.sh.log`: the command and settings used to run Tempo.
- `output.html`: this document.
- `execution_report`, `execution_timeline`, `execution_trace`: Nextflow
  reports on the run's jobs.
