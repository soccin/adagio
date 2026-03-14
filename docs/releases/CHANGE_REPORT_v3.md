# Adagio v3 Change Report

Changes from v2.4.2 (2025-09-24) to v3.0 (2026-03-14).

---

## Overview

v3 is a major release with four broad areas of change:

1. **IRIS cluster support** — full WES and WGS pipeline operation on the IRIS/SLURM cluster
2. **Post-processing and reporting** — new and improved reports (SNV, germline, SV, QC, FACETS,
   TERT, WGS stats), plus a Nextflow trace/failure report
3. **Resource optimization** — revised CPU/memory allocations for both JUNO (LSF) and IRIS (SLURM)
4. **Bug fixes** — germline deduplication, SV report sample coverage, TERT promoter retention,
   and several script correctness issues

The underlying tempo submodule was advanced to the **Cordelia** branch (`cordelia-01` tag,
commit `957a2949`).

---

## 1. IRIS Cluster Support

### New configuration files

| File | Purpose |
|---|---|
| `conf/iris.config` | SLURM executor, queue, and global settings for IRIS |
| `conf/tempo-wes-iris.config` | Process-specific CPU/memory for WES on IRIS |
| `conf/tempo-wgs-iris.config` | Process-specific CPU/memory for WGS on IRIS |

### Key changes

- `conf/neo.config` renamed to `conf/juno.config` to match cluster naming convention.
- All Nextflow config files standardized to `.config` extension (previously some used `.conf`).
- `TEMPO_PROFILE` is now set dynamically: `iris` on IRIS, `juno` on JUNO. Previously it was
  hardcoded to `juno`, silently mis-configuring IRIS runs.
- `publish_dir_mode = "copy"` added to IRIS config for nf-core module compatibility.
- Blocking error messages that prevented WES and WGS from running on IRIS have been removed;
  memory configurations are now resolved.
- `bin/runTempoWESCohort.sh` and `bin/runTempoWGSBam.sh` now select the correct cluster config
  file via a `PIPELINE_CONFIG` variable based on detected cluster.

---

## 2. SLURM Job Submission

`bin/runTempoWESCohort.sh` and `bin/runTempoWGSBam.sh` now carry SBATCH directives so they
can be submitted directly via `sbatch`:

```
#SBATCH --job-name  ...
#SBATCH --output    ...
#SBATCH --cpus-per-task 4
#SBATCH --time      7-00:00:00
#SBATCH --partition cmobic_cpu,cmobic_pipeline
```

A `SBATCH_SCRIPT_DIR` environment variable check is included to handle the path issue where
sbatch copies scripts to a temporary directory, breaking relative path resolution.

---

## 3. Pipeline Run Scripts

### Workflow customization (`runTempoWESCohort.sh`, `runTempoWGSBam.sh`)

- Default workflows are now `snv,qc,facets` (removed `sv`, `mutsig`, `msisensor` from defaults).
- Two new flags let callers override or extend workflows at runtime:
  - `--workflows <list>` — replace defaults entirely
  - `--add-workflows <list>` — append to defaults

### Nextflow Trace Report

A new `scripts/nfTraceReport.R` script is invoked automatically after each pipeline run and
its output is saved as `RUN_REPORT_YYMMDD_.md` alongside the run.

- Parses Nextflow trace files to summarize process status counts.
- Identifies all FAILED/ABORTED process instances with detail.
- For failed jobs, queries SLURM `seff` to retrieve final job state.
- Prints formatted tables to stdout (captured to the markdown report file).
- Marks processes as WARN if some tasks completed, ERROR if none completed.
- Helper libraries: `scripts/rsrc/nf-reports/trace_parser.R`,
  `scripts/rsrc/nf-reports/nextflow_analysis.R`,
  `scripts/rsrc/nf-reports/slurm_utils.R`.

The `nfTraceReport.R` run was also moved to after the Nextflow block (using `pushd`/`popd`
instead of `cd`) so that trace files are present when the report is generated.

---

## 4. Post-Processing (`bin/doPost.sh`, `bin/doGermlinePost.sh`)

- Echo statements added throughout `doPost.sh` to show which R scripts are executing.
- Pipeline info file collection simplified from complex `find` commands to direct glob patterns
  (`out/*/pipeline_info/*.{html,txt,pdf}`).
- `getWGSStats.R` is now guarded with an `if [ "$ASSAY" == "genome" ]` check so it does not
  run on WES/panel assays.
- Germline post-processing (`doGermlinePost.sh`): ASSAY_TYPE now detected from `cmd.sh.log`;
  `reportGermSV01.R` only runs for genome assays. Premature `exit` removed so `version.txt`
  logging completes.

---

## 5. Delivery Scripts

### `bin/deliver.sh` and `bin/deliverGermline.sh`

- BIC_DELIVERY path changed from hardcoded `/rtsess01/.../socci/...` to `$HOME/Code/BIC/Delivery/Version2j`.
- `readme2yaml.R` call updated from `tempo` to `adagio` argument.
- Added `module purge`, `module load python/3.8.0`, `module load py-python-ldap/3.4.2`
  before the `init_impact_project_permissions.py` call.
- `deliverGermline.sh` now includes the same BIC_DELIVERY + module + permissions steps.

---

## 6. Reporting Scripts

### `scripts/report01.R` (SNV somatic report)

- Output file version bumped from `v2` to `v3` (`SNV_Report01_v3.xlsx`).
- Project name handling: if the output directory name lacks a `Proj_` prefix, it is now
  prepended automatically (handles both `Proj_XXXXX` and bare `XXXXX` formats).
- MAF reading switched from `read_tsv` to `data.table::fread` to avoid column parsing issues
  with large MAF files.
- `/metrics` directory is now filtered out when parsing the output path for project number
  extraction.
- Non-synonymous mutation count added to the Samples sheet.
- **TERT promoter fix**: The filter `!is.na(Alteration)` previously silently dropped TERT
  promoter mutations (`Variant_Classification == "5'Flank"`, no `HGVSp_Short`). The filter
  now explicitly retains them:
  ```r
  filter((!is.na(Alteration) & !grepl("=$", Alteration)) | (Gene=="TERT" & Type=="5'Flank"))
  ```
  Only `5'Flank` TERT variants are kept; other TERT variants with NA Alteration (intronic,
  3'UTR, etc.) remain excluded.

### `scripts/reportGerm01.R` (germline report)

- Report version bumped from v2 to v3.
- **Germline deduplication**: added `distinct()` on variant position, alleles, and sample
  barcode to remove duplicate entries that arise when the same normal sample is used for
  multiple tumor samples.
- **TERT promoter fix** (same logic as somatic): the previous two-filter approach
  `filter(!is.na(Alteration) | Gene=="TERT")` + `filter(!grepl("=$", Alteration))` was
  imprecise. Replaced with the single unified filter:
  ```r
  filter((!is.na(Alteration) & !grepl("=$", Alteration)) | (Gene=="TERT" & Type=="5'Flank"))
  ```

### `scripts/reportSV01.R` (structural variant report)

- Updated to v5.
- BEDPE file pattern changed from `.final.clustered.bedpe` to `.final.bedpe` to handle cases
  where the clustering step fails.
- All tumor samples now appear in the SV report even when they have zero structural variants
  (previously, samples with no SV BEDPE files were silently omitted from the SampleData sheet).
- Fixed misnamed variable `event_counts` → `sv_counts`.
- Tidyverse-style refactoring: `|>` pipe throughout, descriptive variable names
  (`sv_files`, `sv_data`, `sv_events`), explicit `join_by()`, `show_col_types = FALSE`.
- `scripts/rsrc/read_tempo_sv.R` updated: `type_convert()` corrected; empty SV data handled
  gracefully; package startup messages suppressed.

### `scripts/reportTERT.R` (new)

New dedicated TERT mutation report. Extracts all TERT gene mutations from the somatic MAF
and writes `Proj_<projNo>_TERT_Muts_v1.xlsx`.

### `scripts/qcReport01.R` (QC report)

- WGS support: conditional check for `hs_metrics` files; sets `phsm = NULL` when absent so
  WGS runs do not fail on missing hybrid-selection metrics.
- `/metrics` directory filtered from output path when extracting project number.
- Validation check for `cohortDir` with informative error message.

### `scripts/reportFacets01.R` (FACETS CNV report)

- Output renamed to `Proj_<projNo>_CNV_Facets_v2.xlsx`.
- Switched from `writexl` to `openxlsx`.
- Three-sheet Excel output: `runInfo` (sample metrics and purity), `armLevel`
  (chromosomal arm gains/losses), `geneLevel` (gene-level copy number).
- QC processing now reads individual `.facets_qc.txt` files instead of a single
  `facetsRpt.xlsx`; failed samples consistently excluded from all output sheets.
- `/metrics` directory filtered from output path.

### `scripts/getWGSStats.R` (new)

New script that collects WGS-specific metrics (coverage, duplication, etc.) from pipeline
output and writes a summary table. Invoked automatically by `doPost.sh` for genome assays only.

---

## 7. Resource Optimization

### JUNO cluster (LSF)

**WES (`conf/tempo-wes-juno.config`)**

- `RunMutect2`: exponential CPU scaling (`2 * task.attempt^2`), fixed 5 GB memory; addresses
  resource contention when many Mutect2 jobs run concurrently.
- `SomaticCombineChannel`: increased memory (4 GB base, 8 GB retry).
- `SomaticAnnotateMaf`: CPU aligned with VEP forks setting (`8 + 4*attempt`), fixed 6 GB.

**WGS (`conf/tempo-wgs-juno.config`)**

- Same RunMutect2 / SomaticCombineChannel / SomaticAnnotateMaf improvements as WES.
- `SomaticDellyCall` / `GermlineDellyCall`: memory increased from 10 GB to 80 GB.
- `RunSvABA`: CPUs increased to 32+ (observed 1561% parallelization in practice), memory
  reduced from 4 GB to 3 GB.
- `SomaticRunManta` / `GermlineRunManta`: CPUs adjusted to `4 + 12*attempt`, memory
  increased from 2 GB to 16 GB.
- Minimum CPU allocation raised from 1 to 2 cores across 30+ processes.

**Resource allocation strategy**: the retry strategy was inverted from
`fixed CPUs + scaling memory` to `scaling CPUs + fixed memory`. This provides a "CPU cushion"
on retries while keeping memory-per-core predictable on JUNO's per-core allocation model.

### IRIS cluster (SLURM)

**WES (`conf/tempo-wes-iris.config`)** and **WGS (`conf/tempo-wgs-iris.config`)**

- Comprehensive per-process CPU, memory, and wall-time configurations added for:
  AlignReads, GATK4SPARK processes (MarkDuplicates, SetNmMdAndUqTags, BaseRecalibrator,
  ApplyBQSR), BQSR operations, BAM merging/indexing, somatic callers, QC processes.
- Dynamic scaling via `task.attempt` for retries.
- `AlignReads` base CPUs reduced from 16 to 8 (scales on retry).
- `QcQualimap` memory changed from `128.GB * task.attempt` to
  `128.GB + 128.GB * task.attempt` (guarantees 256 GB minimum on first attempt).

---

## 8. Tempo Submodule

Updated from commit `00eb724` to `957a2949` (tag `cordelia-01`, branch `ccs/update-250925`,
forked 2025-09-25). The Cordelia branch incorporates:

- `patch/01-maxRecsInRam` merge (GATK memory parameter fix)
- `enhancement/separating_hlatyping_and_lohhla_wf`
- Various upstream merges and pipeline improvements

---

## 9. Script Archival and Cleanup

- `scripts/runReport.R` moved to `scripts/attic/` (replaced by `nfTraceReport.R`).
- `scripts/downSampleBam.sh`: added SBATCH directives, usage function, input validation, and
  portable `NPROC` variable; deprecated `picardV2` command replaced with `picard`.

---

## Files Changed (summary)

| Area | Files |
|---|---|
| Pipeline run scripts | `bin/runTempoWESCohort.sh`, `bin/runTempoWGSBam.sh` |
| Post-processing | `bin/doPost.sh`, `bin/doGermlinePost.sh` |
| Delivery | `bin/deliver.sh`, `bin/deliverGermline.sh` |
| Cluster config | `conf/iris.config`, `conf/juno.config`, `conf/tempo-wes-iris.config`, `conf/tempo-wgs-iris.config`, `conf/tempo-wes-juno.config`, `conf/tempo-wgs-juno.config` |
| Reports | `scripts/report01.R`, `scripts/reportGerm01.R`, `scripts/reportSV01.R`, `scripts/reportFacets01.R`, `scripts/qcReport01.R`, `scripts/reportTERT.R` (new), `scripts/getWGSStats.R` (new) |
| Trace reporting | `scripts/nfTraceReport.R` (new), `scripts/rsrc/nf-reports/trace_parser.R`, `scripts/rsrc/nf-reports/nextflow_analysis.R`, `scripts/rsrc/nf-reports/slurm_utils.R` (new) |
| Utilities | `scripts/rsrc/read_tempo_sv.R`, `scripts/downSampleBam.sh` |
| Submodule | `tempo/` (cordelia-01) |
