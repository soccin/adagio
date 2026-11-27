# QC background database (qcdb)

`buildQCDb.R` collects every QC output of one or more finished adagio
(Tempo) runs into one `.rds` file. The database gives the expected
range of each QC metric for an assay, so a project's QC report can show
each sample against a background set rather than against fixed cutoffs.

The WES IDT v2 background combines two runs:

- 200 IGO tumor/normal pairs selected to be typical in data size
  (NovaSeq 6000 and NovaSeq X); see
  `Resources/QCDb/WES/IDT_v2/Version_261121/inputs/README.md`
- 76 NovaSeq X DMP pairs (`Resources/QCDb/WES/IDT_v2/Version_261125`)

`samples$SEQ_TECH` gives each sample's sequencer technology, as
`qcReport02.R` computes it, and `PROJECT_ID` its run.

## Build

For each run, from its project folder (the one that holds `out/`),
first run `<adagio>/scripts/picardqc/doPicardQC.sh` (uncapped
HsMetrics and AlignmentSummaryMetrics) and wait for its array job.
Then submit one build over all the runs. `--out` and `--lims` take
comma-separated lists:

```
sbatch --export=ALL,SBATCH_SCRIPT_DIR=<adagio>/scripts/qcdb \
    <adagio>/scripts/qcdb/runBuildQCDb.sh \
    --out=<run1>/out/<PROJECT_ID1>,<run2>/out/<PROJECT_ID2> \
    --lims=<run1>/inputs/samples.csv,<run2>/inputs/samples.csv
```

With one run, `--out` can be left out when the project folder has a
single `out/<PROJECT_ID>`. Each run's pairing is read from its run log;
`--pairing`, `--hsmetrics` and `--asm` override it, with one value per
`--out` folder in the same order. A sample may be in only one run.

Output: `qcdb/qcdb_<assay>_<version>.rds` in the folder the job is
submitted from. The version is the build date, `yymmdd`, unless
`--version` sets it. The builder stops at the start if the file exists,
so a second build on the same day needs `--version` (for example
`261123b`). `--dest` writes elsewhere (use it for test builds).
`Rscript buildQCDb.R --help` lists every option.

The build also needs two resources made once per target set:

- the GC of each target, `<adagio>/assets/qcdb/IDT_Exome_v2_FP_b37_targets.plus5bp.gc.tsv.gz`
  (`--target-gc` for another assay), made by `makeTargetGC.R` from one
  sample's Alfred file, so the intervals are exactly those of Alfred's
  `TC` section (197,379 unique targets: the padded BED without its last
  4 chrY rows). GC is (G + C) / (A + C + G + T) on
  `human_g1k_v37_decoy.fasta`; 139 targets that are all N (124 in the
  chrY PAR, which this reference masks) have GC `NA`:

  ```
  sbatch --export=ALL,SBATCH_SCRIPT_DIR=<adagio>/scripts/qcdb \
      <adagio>/scripts/qcdb/runMakeTargetGC.sh \
      --alfred=out/<PROJECT_ID>/bams/<SAMPLE>/alfred/<SAMPLE>.alfred.tsv.gz \
      --fasta=<reference>.fasta --out=<adagio>/assets/qcdb/<targets>.gc.tsv.gz
  ```

- the gene lists and gene-to-target map of the missed-variant
  likelihood, from `scripts/qcgenes/buildQCGenes.R` (`--genes`;
  default `QC_GENES_DIR` in `scripts/rsrc/qc_pair_data.R`)

## Storage and lookup

The `.rds` files are not stored in git. They stay on shared storage,
and the tracked index `<adagio>/assets/qcdb/qcdb_index.tsv` lists
where each one is:

| Column | Contents |
|---|---|
| `ASSAY` | assay label (`--assay`) |
| `VERSION` | build date, `yymmdd`, or the `--version` label |
| `DATE` | build date, `YYYY-MM-DD` |
| `PATH` | absolute path to the `.rds` |

The builder prints the index line at the end of a build; add it to
the index by hand. Reports find a database with `rsrc/qcdb_index.R`:
`find_qcdb(adagio, assay)` returns the path of the newest version for
the assay (`version=` picks a specific one, `qcdb=` overrides the
index), and `load_qcdb()` reads it.

The build reads about 400 Alfred files of ~500k lines each, so it runs
as a SLURM job (8 cores, under 2 h; about 4 min for 400 samples).

Versions in the index:

| Version | HsMetrics | Notes |
|---|---|---|
| `261122` | Tempo's files, cap 200 | first draft; tumor median coverage capped |
| `261123` | `post/qc`, cap 1000 | same 200 pairs |
| `261123b` | `post/qc`, cap 1000 | current; adds `ASM_` (AlignmentSummaryMetrics) |

## Layout

`qcdb <- readRDS("qcdb_WES_IDT_v2_<yymmdd>.rds")` is a list:

| Element | Contents |
|---|---|
| `meta` | version, assay, build time, source runs, sample and pair counts (by run and by sequencer technology), adagio and tempo commits (`adagio_dirty` TRUE if the working tree had changes), the GC table and gene resources used, notes |
| `samples` | one row per sample and pair: `SAMPLE`, `TYPE` (Tumor/Normal), `PAIR`, `PROJECT_ID` (run), `SEQ_TECH` and `INSTRUMENT` (`qcdb_seq_tech.R`), plus LIMS columns if `--lims` was given |
| `pairs` | `PAIR`, `TUMOR_ID`, `NORMAL_ID`, `PROJECT_ID` |
| `sample_metrics` | one row per sample, one column per metric (wide) |
| `pair_metrics` | one row per pair, one column per metric (wide) |
| `sample_metrics_long`, `pair_metrics_long` | the numeric metrics in long form: `SAMPLE`/`PAIR`, `TYPE`, `SOURCE`, `METRIC`, `VALUE` |
| `reference` | per metric and `TYPE` (Normal, Tumor, All, Pair): N, mean, SD, median, MAD, min, max, quantiles 1-99%, over all runs and sequencer technologies |
| `target_coverage` | per target and `TYPE`: median coverage, median/5%/95% of coverage normalized to each sample's median, fraction of samples below 0.2x |
| `dist` | distributions, one long tibble each (see below) |
| `pipeline` | Nextflow resource use per run and process (tasks, failures, attempts, realtime, peak RSS) |
| `completeness` | which samples and pairs have each source (`GENE_MVLH` is `NA` for normals), and files that failed to parse |
| `dictionary` | every column of the two metric tables with its class and source |

Column names start with their source:

| Prefix | Source | Level |
|---|---|---|
| `HSM_` | Picard CollectHsMetrics | sample |
| `ASM_` | Picard CollectAlignmentSummaryMetrics, `PAIR` row | sample |
| `ALFRED_` | Alfred summary (ME), on-target rate, chrX/chrY observed/expected | sample |
| `TARGET_` | Alfred per-target coverage: uncapped median (`TARGET_MEDIAN_COV`) and uniformity summaries | sample |
| `QUALIMAP_` | Qualimap bamqc `genome_results.txt` | sample |
| `FASTP_` | fastp, summed over lanes (rates recomputed) | sample |
| `CONPAIR_` | Conpair contamination (fraction) and concordance (percent) | sample, pair |
| `TEMPO_` | Tempo QC status, `sample_data.txt` (purity, ploidy, TMB) | sample, pair |
| `FACETS_` | facets-suite QC row (`facets_qc.txt`); `FACETS_N_HOMDEL_GENES` from `gene_level.txt` (PASS and RESCUE calls) | pair |
| `MAF_` | `somatic.final.maf` summary | pair |
| `MAFUNFILT_` | `somatic.unfiltered.maf` summary | pair |
| `MANTA_` | Manta somatic SV counts | pair |

`HSM_` metrics come from `out/<PROJECT_ID>/post/qc`, written by
`scripts/picardqc/doPicardQC.sh`, which reruns Picard with
`COVERAGE_CAP 1000`. Tempo's own files use Picard's default cap of 200,
which caps `HSM_MEDIAN_TARGET_COVERAGE`, `HSM_FOLD_80_BASE_PENALTY`,
`HSM_HS_PENALTY_*` and `hsm_coverage`; about half of tumors sit at the
cap. Run `doPicardQC.sh` before the build. `--hsmetrics=DIR` reads
another folder (`<out>/bams` for Tempo's files). The folder and the cap
are recorded in `meta`. `TARGET_MEDIAN_COV` is the Alfred median; it
counts duplicates, so it runs higher than Picard's.

`ASM_` metrics come from `out/<PROJECT_ID>/post/qc/<SAMPLE>.asm.txt`,
also written by `doPicardQC.sh` (Tempo does not run this tool;
`--asm=DIR` reads another folder). They are the `PAIR` row, over all
reads including duplicates: for example `ASM_PCT_CHIMERAS`,
`ASM_PF_MISMATCH_RATE`, `ASM_PCT_PF_READS_ALIGNED`, `ASM_STRAND_BALANCE`.
`ASM_PCT_ADAPTER` is close to 0 because fastp trims adapters before
alignment.

`FACETS_N_HOMDEL_GENES` is the number of genes with `cn_state` HOMDEL
in `facets/<pair>/facets0.5.14c100pc500/<pair>.gene_level.txt` with
`filter` PASS or RESCUE (QSee's "Deleted genes"). Calls facets-suite
suppresses (`suppress_large_homdel`, `suppress_segment_too_large`) are
left out: in the background they are 95% of HOMDEL gene rows, up to
6,536 genes in one pair. `FACETS_n_homdels` counts segments instead: 3
for P-0137506, which has 9 HOMDEL genes, all PASS.

`dist` elements:

| Element | Contents |
|---|---|
| `hsm_coverage` | Picard target coverage histogram (to the cap in `meta`, 1000x by default) |
| `asm_categories` | Picard AlignmentSummaryMetrics, all three rows (`FIRST_OF_PAIR`, `SECOND_OF_PAIR`, `PAIR`) |
| `alfred_insert_size` | insert size counts, 0-1000 bp, all layouts summed |
| `alfred_coverage` | genome-wide coverage histogram, 0-500x |
| `alfred_gc` | GC content of reads, sample and reference |
| `alfred_base_qual` | mean base quality by read position |
| `alfred_map_qual` | mapping quality histogram |
| `alfred_chrom_map` | mapped reads per chromosome with observed/expected ratio |
| `alfred_indel_size`, `alfred_indel_context` | indel sizes and homopolymer context |
| `alfred_on_target` | on-target rate by target extension |
| `fastp_lanes` | fastp summary per lane |
| `fastp_dup_hist` | fastp duplication histogram per lane: `SAMPLE`, `LANE_TAG`, `DUP_LEVEL` (1-31; 31 is 31 or more), `N_SETS`, `MEAN_GC` (`NA` where `N_SETS` is 0) |
| `target_gc_bias` | GC-bias curve per sample: `SAMPLE`, `GC_BIN` (midpoint of a 1% bin), `N_TARGETS`, `MEDIAN_NORM_COV`, `Q25_NORM_COV`, `Q75_NORM_COV` |
| `gene_mvlh` | missed-variant likelihood per tumor and OncoKB gene: `SAMPLE`, `GENE`, `MVLH`, `MEAN_DEPTH` |
| `gene_mvlh_samples` | the inputs of `gene_mvlh`, one row per tumor: `SAMPLE`, `PAIR`, `HSM_MEAN_TARGET_COVERAGE`, `PURITY` (FACETS), `SEX_CALL` (the normal's), `REPORTED_SEX` (LIMS), `MALE`, `N_GENES` |
| `maf_spectrum96` | 96-channel SNV counts per pair (final MAF) |
| `maf_unfiltered_filters` | count of each FILTER value per pair (unfiltered MAF) |

### fastp duplication histogram (`fastp_dup_hist`)

From each lane's fastp JSON, `duplication$histogram` and
`duplication$mean_gc` (`read_fastp_dup_hist()`). In fastp 0.19.7
(Tempo's; `src/duplicate.cpp`) each read pair goes into one of 4^12
buckets by the first 12 bases of R1. A bucket keeps one representative,
the pair whose first 32 bases of R2 are smallest, and counts how often
that exact sequence was seen; other sequences in the bucket are not
counted. Element j is the number of buckets whose representative was
seen j times. So the histogram is a sample of distinct fragments, about
one per bucket: 10.8M of 49.5M pairs for P-0137506-T01-WES lane 3.
fastp's `duplication_rate` is sum(count - 1) / sum(count), which the
histogram gives up to the open last bin.

Caveats:

- It is per lane: duplicates in different lanes are not seen, so set
  sizes are low for libraries split over lanes.
- It is sequence-based, before alignment.
- Sequencing errors in the key bases split sets.

For P-0137506-T01-WES the fastp rate is 8.2%, against Alfred's
duplicate fraction of 13.8%.

### GC-bias curves (`target_gc_bias`)

`target_gc_curve()`: each target's Alfred `TC` coverage divided by the
sample's median target coverage (as for `target_coverage`), then the
median per 1% GC bin over the autosomal targets, with the GC table
above. Targets listed twice in `TC` count once; bins with fewer than
100 targets are dropped. Alfred's coverage counts duplicates; dividing
by the median removes most of that. A typical curve is 1.05-1.1 in the
40-50% bins.

### Missed-variant likelihood (`gene_mvlh`)

`tumor_gene_mvlh()` calls `gene_mvlh()` from
`scripts/rsrc/qc_pair_data.R` with the arguments the per-pair QC pages
use, so background and project values are the same computation:

- genes: the OncoKB genes of the gene resources with half or more of
  their coding bases in the targets; only coding bases inside the
  targets count (`uncaptured = "drop"`)
- depth: each target's Alfred mean coverage for all its bases,
  rescaled so the length-weighted mean of the sample's target coverage
  equals `HSM_MEAN_TARGET_COVERAGE` (Alfred counts duplicates and has no
  MAPQ or base-quality filter; Picard has both)
- VAF: purity / alleles; purity is the pair's `FACETS_purity`, alleles
  is 1 on chrX and chrY in a male, else 2
- male: the normal's sex call (`call_normal_sex()`, `scripts/rsrc/qc_sex.R`)
  is Male, or it is not Female and the LIMS sex is Male (`mvlh_male()`)
- MVLH at a base: the chance of fewer than 3 alt reads; gene MVLH is
  the mean over its bases

Tumors only (Tempo is a somatic pipeline). A tumor with no FACETS
purity has no rows; `gene_mvlh_samples` and `completeness$samples`
list them. Using a target's mean depth for all its bases ignores depth
changes inside the target, so the MVLH is lower than a per-base
calculation would give.

## Project side

`rsrc/qcdb_project_metrics.R` computes the same values for one
project, with the same functions:

| Function | Database table |
|---|---|
| `project_sample_metrics()` | `sample_metrics` |
| `project_pair_metrics()` | `pair_metrics` (Conpair, `TEMPO_`, `FACETS_` including `FACETS_N_HOMDEL_GENES`, `MANTA_`; not the MAF summaries or the Tempo pair status) |
| `project_sample_dists()` | `dist$fastp_dup_hist`, `dist$target_gc_bias` (pass `read_target_gc(qcdb$meta$target_gc_file)`) |
| `project_gene_mvlh()` | `dist$gene_mvlh` (pass one row per tumor with `SAMPLE`, `HSM_MEAN_TARGET_COVERAGE`, `PURITY`, `MALE`; needs `scripts/rsrc/qc_pair_data.R`) |

## Example

```r
source(file.path(adagio, "scripts", "qcdb", "rsrc", "qcdb_index.R"))
qcdb <- load_qcdb(adagio, "WES_IDT_v2")
qcdb$reference |> filter(METRIC == "HSM_MEAN_TARGET_COVERAGE")
qcdb$sample_metrics |> select(SAMPLE, TYPE, HSM_MEAN_TARGET_COVERAGE, CONPAIR_CONTAMINATION)
```

## Files

- `buildQCDb.R`: builds the database
- `runBuildQCDb.sh`: SLURM wrapper
- `makeTargetGC.R`, `runMakeTargetGC.sh`: build the per-target GC table
- `rsrc/qcdb_readers.R`: one reader per QC file type, and the
  per-sample computations shared with the project side
  (`target_gc_curve()`, `tumor_gene_mvlh()`, `mvlh_male()`)
- `rsrc/qcdb_project_metrics.R`: the same metrics for one project
- `rsrc/qcdb_index.R`: finds a database through the index
- `rsrc/qcdb_seq_tech.R`: sequencer technology from the fastp file names
- `<adagio>/assets/qcdb/qcdb_index.tsv`: where each database is stored
- `<adagio>/assets/qcdb/IDT_Exome_v2_FP_b37_targets.plus5bp.gc.tsv.gz`:
  GC of each IDT v2 target
