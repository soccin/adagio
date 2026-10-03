# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Adagio** is a somatic/germline variant calling pipeline wrapper around [Tempo](https://github.com/mskcc/tempo), a Nextflow DSL2 pipeline for tumor-normal WGS/WES analysis. It wraps Tempo with cluster-aware run scripts, custom R post-processing reports, and delivery tooling for MSK BIC.

- Current version: **v3.2.1** (Cordelia)
- Tempo submodule at `tempo/` (branch `devs-iris`)
- Runs on **IRIS** (SLURM) only — see [HPC clusters](#hpc-clusters) for the
  scheduling rules
- **JUNO (LSF) was shut down for good on 2026-10-01.** Its code and config are
  still in the repo but are dead; leave them untouched until they are removed.

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
1. `conf/iris.config` — cluster executor settings
2. `conf/tempo-{wgs|wes}-iris.config` — per-process resource overrides

The `conf/*juno*.config` files are dead (JUNO is shut down).

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

### JUNO was shut down on 2026-10-01 — do not touch its code

**JUNO is gone for good.** Nothing can run there, so the JUNO code paths are dead
code that a later release will remove. Until then, leave them as they are: do
not edit them, do not modernize them, do not port IRIS changes onto them, and do
not "fix" differences between the IRIS and JUNO configs. A difference is not a
bug.

Dead JUNO paths:

- `conf/juno.config`, `conf/tempo-wgs-juno.config`, `conf/tempo-wes-juno.config`
- `docs/JUNO_LSF.md` (historical reference)
- the `JUNO` branches in the `bin/` run scripts and any
  `workflow.profile == "juno"` blocks in `tempo/`

If a change would touch a JUNO path, make the IRIS change only and say what was
left alone.

**Not JUNO code despite the name:** tempo's `iris` profile loads
`tempo/conf/juno.config`, `tempo/conf/resources_juno.config` and
`tempo/conf/resources_juno_genome.config`. IRIS runs depend on these files. Do
not delete them when the JUNO paths are removed.

**IRIS is the only supported cluster.**

**IRIS is SLURM. JUNO was LSF. Do not copy settings from the JUNO configs.**
**Read `docs/IRIS_SLURM.md` before changing any resource setting:**

| Cluster | Reference | Status |
|---|---|---|
| IRIS | **`docs/IRIS_SLURM.md`** | verified 2026-07-18 against the live scheduler |
| JUNO | **`docs/JUNO_LSF.md`** | historical; cluster shut down 2026-10-01 |

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
- **JUNO was flat and generous:** LSF, no queue tiering, `time = { 500.h }`
  throughout, `-R 'cmorsc1'`, `maxRetries = 3`.
- **Never copy settings from the JUNO configs.** JUNO's 500 h strands a job on
  IRIS's 19-node partition; `mem_per_core` flips `true` (JUNO) to `false` (IRIS),
  so a per-core memory figure silently under-requests by a factor of `cpus`; and
  IRIS caps retries at 2, truncating a 3-attempt ramp.

## Running the pipeline

### Environment setup

No setup step is required. The run scripts resolve `$CLUSTER` themselves and
export `NXF_SINGULARITY_CACHEDIR`, `TMPDIR`, `WORKDIR`, `REFERENCE_BASE`, and
`PATH` for the detected cluster.

Optionally set `NXF_HOME` in your shell profile to keep Nextflow's framework
jars, plugins, and assets out of `$HOME`:

```bash
export NXF_HOME=/scratch/core001/bic/socci/opt/nextflow
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
bin/clean.sh   # removes out*/ work/ .nextflow.log* trace* report.html timeline.html *.tsv
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
