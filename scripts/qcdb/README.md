# QC background database (qcdb)

`buildQCDb.R` collects every QC output of a finished adagio (Tempo) run
into one `.rds` file. The database gives the expected range of each QC
metric for an assay, so a project's QC report can show each sample
against a background set rather than against fixed cutoffs.

The first database is built from 200 IGO WES tumor/normal pairs (IDT v2
exome) selected to be typical in data size; see
`Resources/QCDb/WES/IDT_v2/Version_261121/inputs/README.md`.

## Build

Submit from the project folder (the one that holds `out/`):

```
sbatch --export=ALL,SBATCH_SCRIPT_DIR=<adagio>/scripts/qcdb \
    <adagio>/scripts/qcdb/runBuildQCDb.sh \
    --pairing=inputTempo_pairing.tsv \
    --lims=inputs/TN_pairs_200_samples.csv
```

Output: `qcdb/qcdb_<assay>_<yymmdd>.rds` in the project folder. The
date in the name is the version. `--dest` writes elsewhere (use it for
test builds). `Rscript buildQCDb.R --help` lists every option.

## Storage and lookup

The `.rds` files are not stored in git. They stay on shared storage,
and the tracked index `<adagio>/assets/qcdb/qcdb_index.tsv` lists
where each one is:

| Column | Contents |
|---|---|
| `ASSAY` | assay label (`--assay`) |
| `VERSION` | build date, `yymmdd` |
| `PATH` | absolute path to the `.rds` |

The builder prints the index line at the end of a build; add it to
the index by hand. Reports find a database with `rsrc/qcdb_index.R`:
`find_qcdb(adagio, assay)` returns the path of the newest version for
the assay (`version=` picks a specific one, `qcdb=` overrides the
index), and `load_qcdb()` reads it.

The build reads about 400 Alfred files of ~500k lines each, so it runs
as a SLURM job (8 cores, under 2 h).

## Layout

`qcdb <- readRDS("qcdb_WES_IDT_v2_<yymmdd>.rds")` is a list:

| Element | Contents |
|---|---|
| `meta` | version, assay, build time, source run, sample and pair counts, adagio and tempo commits, notes |
| `samples` | one row per sample: `SAMPLE`, `TYPE` (Tumor/Normal), `PAIR`, plus LIMS columns if `--lims` was given |
| `pairs` | `PAIR`, `TUMOR_ID`, `NORMAL_ID` |
| `sample_metrics` | one row per sample, one column per metric (wide) |
| `pair_metrics` | one row per pair, one column per metric (wide) |
| `sample_metrics_long`, `pair_metrics_long` | the numeric metrics in long form: `SAMPLE`/`PAIR`, `TYPE`, `SOURCE`, `METRIC`, `VALUE` |
| `reference` | per metric and `TYPE` (Normal, Tumor, All, Pair): N, mean, SD, median, MAD, min, max, quantiles 1-99% |
| `target_coverage` | per target and `TYPE`: median coverage, median/5%/95% of coverage normalized to each sample's median, fraction of samples below 0.2x |
| `dist` | distributions, one long tibble each (see below) |
| `pipeline` | Nextflow resource use per process (tasks, failures, attempts, realtime, peak RSS) |
| `completeness` | which samples and pairs have each source, and files that failed to parse |
| `dictionary` | every column of the two metric tables with its class and source |

Column names start with their source:

| Prefix | Source | Level |
|---|---|---|
| `HSM_` | Picard CollectHsMetrics | sample |
| `ALFRED_` | Alfred summary (ME), on-target rate, chrX/chrY observed/expected | sample |
| `TARGET_` | Alfred per-target coverage: uncapped median (`TARGET_MEDIAN_COV`) and uniformity summaries | sample |
| `QUALIMAP_` | Qualimap bamqc `genome_results.txt` | sample |
| `FASTP_` | fastp, summed over lanes (rates recomputed) | sample |
| `CONPAIR_` | Conpair contamination (fraction) and concordance (percent) | sample, pair |
| `TEMPO_` | Tempo QC status, `sample_data.txt` (purity, ploidy, TMB) | sample, pair |
| `FACETS_` | facets-suite QC row (`facets_qc.txt`) | pair |
| `MAF_` | `somatic.final.maf` summary | pair |
| `MAFUNFILT_` | `somatic.unfiltered.maf` summary | pair |
| `MANTA_` | Manta somatic SV counts | pair |

Picard runs with `COVERAGE_CAP 200`, so `HSM_MEDIAN_TARGET_COVERAGE`
and `hsm_coverage` stop at 200x; most tumors reach the cap. Use
`TARGET_MEDIAN_COV` for an uncapped median (it counts duplicates, so it
runs higher than Picard).

`dist` elements:

| Element | Contents |
|---|---|
| `hsm_coverage` | Picard target coverage histogram (capped at 200x) |
| `alfred_insert_size` | insert size counts, 0-1000 bp, all layouts summed |
| `alfred_coverage` | genome-wide coverage histogram, 0-500x |
| `alfred_gc` | GC content of reads, sample and reference |
| `alfred_base_qual` | mean base quality by read position |
| `alfred_map_qual` | mapping quality histogram |
| `alfred_chrom_map` | mapped reads per chromosome with observed/expected ratio |
| `alfred_indel_size`, `alfred_indel_context` | indel sizes and homopolymer context |
| `alfred_on_target` | on-target rate by target extension |
| `fastp_lanes` | fastp summary per lane |
| `maf_spectrum96` | 96-channel SNV counts per pair (final MAF) |
| `maf_unfiltered_filters` | count of each FILTER value per pair (unfiltered MAF) |

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
- `rsrc/qcdb_readers.R`: one reader per QC file type
- `rsrc/qcdb_index.R`: finds a database through the index
- `<adagio>/assets/qcdb/qcdb_index.tsv`: where each database is stored
