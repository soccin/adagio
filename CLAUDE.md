# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Adagio** is a somatic/germline variant calling pipeline wrapper around [Tempo](https://github.com/mskcc/tempo), a Nextflow DSL2 pipeline for tumor-normal WGS/WES analysis. It wraps Tempo with cluster-aware run scripts, custom R post-processing reports, and delivery tooling for MSK BIC.

- Current version: **v3.1.0** (Cordelia)
- Tempo submodule at `tempo/` (branch `ccs/update-250925`)
- Runs on two HPC clusters: **JUNO** (LSF) and **IRIS** (SLURM) — see
  [HPC clusters](#hpc-clusters) for the scheduling rules; they are not
  interchangeable

## Architecture

```
adagio/
├── tempo/           # Nextflow pipeline submodule (dsl2.nf is the entry point)
├── bin/             # Run scripts and helpers
├── conf/            # Nextflow config overrides per cluster/assay
├── scripts/         # R post-processing reports
│   └── rsrc/        # Shared R source files (read_tempo_sv.R, add_sv_scores.R)
├── docs/            # Pipeline documentation
└── devs/            # Development branches / patches / roadmap
```

### Pipeline entry points

| Script | Purpose |
|--------|---------|
| `bin/runTempoWGSBam.sh` | Run WGS from BAMs (SLURM-submittable) |
| `bin/runTempoWESCohort.sh` | Run WES from FASTQs/BAMs (SLURM-submittable) |
| `bin/doPost.sh` | Run all post-processing R reports after pipeline completes |
| `bin/deliver.sh` | Deliver results to a delivery folder |

### Config layering

Each run loads two Nextflow config files:
1. `conf/{juno|iris}.config` — cluster executor settings
2. `conf/tempo-{wgs|wes}-{juno|iris}.config` — per-process resource overrides

### Post-processing reports (`scripts/`)

All scripts run from the project directory (where `out/` lives):

| Script | Output |
|--------|--------|
| `report01.R <ASSAY>` | Main somatic mutation Excel report |
| `qcReport01.R` | QC metrics report |
| `reportSV01.R` | Somatic SV report (WGS only) |
| `reportFacets01.R` | Copy number / Facets report |
| `reportGerm01.R` | Germline SNV report |
| `reportGermSV01.R` | Germline SV report |
| `getWGSStats.R` | WGS coverage stats (WGS only) |
| `nfTraceReport.R` | Nextflow trace analysis (runs automatically post-pipeline) |

Shared R utilities in `scripts/rsrc/`:
- `read_tempo_sv.R` — parses Tempo `.final.bedpe` SV files
- `add_sv_scores.R` — adds SV evidence scores

## HPC clusters

Cluster is chosen by `$CLUSTER` (`bin/getClusterName.sh`); the run scripts switch
config, Singularity cache, and `REFERENCE_BASE` on it.

**IRIS is SLURM. JUNO is LSF. Assumptions do not transfer between them.**
**Read the relevant reference before changing any resource setting:**

| Cluster | Reference | Status |
|---|---|---|
| IRIS | **`docs/IRIS_SLURM.md`** | verified 2026-07-18 against the live scheduler |
| JUNO | **`docs/JUNO_LSF.md`** | config-derived only; queue names and limits unverified |

IRIS facts are a snapshot and go stale without notice — re-verify via
`docs/IRIS_SLURM.md` section 8 rather than trusting remembered numbers.

Key rules, in full detail in those files:

- **IRIS has a 2-hour door.** `core001` is denied on the 7-day `cpu` partition,
  so the whole general pool is reachable only under a 2 h limit. Capacity cliffs:
  <= 2 h reaches **270** nodes, 2-3 h reaches **37**, > 3 h reaches **19**.
  Creeping past 2 h costs 86% of available hardware; past 3 h, 93%.
- **Never promote a process to a longer IRIS tier on suspicion** — only on a real
  walltime kill at the current tier. "This tool is usually slow" is not evidence.
  Optimise for parallelism, not per-job comfort: a run takes days, and throughput
  binds.
- **On IRIS, escalate on evidence.** Exit 137 = OOM (raise memory, leave the
  partition alone); exit 1 with `caught USR2/TERM signal` = walltime. Fast
  failures are overloaded nodes — retry unchanged, conclude nothing.
- **JUNO is flat and generous:** LSF, no queue tiering, `time = { 500.h }`
  throughout, `-R 'cmorsc1'`, `maxRetries = 3`.
- **Never port settings between the two configs.** JUNO's 500 h strands a job on
  IRIS's 19-node partition; `mem_per_core` flips `true` (JUNO) to `false` (IRIS),
  so a per-core memory figure silently under-requests by a factor of `cpus`; and
  IRIS caps retries at 2, truncating a 3-attempt ramp.

## Running the pipeline

### Environment setup

```bash
source SETENVRC   # sets NXF_SINGULARITY_CACHEDIR, TMPDIR, PATH
```

### WGS from BAMs

```bash
bin/runTempoWGSBam.sh PROJECT_ID BAM_MAPPING.tsv PAIRING.tsv [AGGREGATE.tsv]
# or via SLURM:
sbatch bin/runTempoWGSBam.sh PROJECT_ID BAM_MAPPING.tsv PAIRING.tsv
```

Default WGS workflows: `snv,sv,qc,facets,mutsig`

### WES from FASTQs/BAMs

```bash
bin/runTempoWESCohort.sh PROJECT_ID MAPPING.tsv PAIRING.tsv [AGGREGATE.tsv]
```

Default WES workflows: `snv,qc,facets`

Both scripts support `--workflows=W1,W2,...` to replace defaults and `--add-workflows=W3,...` to extend them. Available workflows: `snv, sv, mutsig, lohhla, facets, msisensor, germsnv, germsv, qc`.

### Post-processing

```bash
bin/doPost.sh    # runs all applicable reports based on ASSAY_TYPE
```

### Resuming a failed run

Before resuming, rotate old logs:
```bash
mkdir passN
mv trace.txt *.html *.tsv passN
```

Then re-run the same script — all run scripts use `-resume` by default.

### Cleanup

```bash
source SETENVRC
clean   # alias: removes out*/ work/ .nextflow.log* trace* report.html timeline.html *.tsv
```

## Commit message conventions

Follow Conventional Commits with scopes: `tempo`, `pipeline`, `docs`, `scripts`, `conf`.

Examples:
```
fix(conf): update QcQualimap memory formula
feat(scripts): add SV evidence scores to report
```

## Installation

Clone with submodules:
```bash
git clone --recurse-submodules <repo>
cd adagio/bin
curl -s https://get.nextflow.io | bash
```
