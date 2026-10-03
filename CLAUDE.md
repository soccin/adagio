# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Adagio** is a somatic/germline variant calling pipeline wrapper around [Tempo](https://github.com/mskcc/tempo), a Nextflow DSL2 pipeline for tumor-normal WGS/WES analysis. It wraps Tempo with cluster-aware run scripts, custom R post-processing reports, and delivery tooling for MSK BIC.

- Current version: **v3.2.2** (Cordelia)
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
│   └── rsrc/        # Shared R source files and reference data (see below)
├── docs/            # Pipeline documentation
└── devs/            # Development branches / patches / roadmap
```

### Pipeline entry points

| Script | Purpose |
|--------|---------|
| `bin/runTempoWGSBam.sh` | Run WGS from BAMs (SLURM-submittable) |
| `bin/runTempoWESCohort.sh` | Run WES from FASTQs (SLURM-submittable) |
| `bin/makeTempoBams.sh` | Tempo alignment only: FASTQs to BQSR BAMs plus a `bamMapping.tsv` (SLURM-submittable) |
| `bin/doPost.sh` | Run the somatic post-processing R reports after the pipeline completes |
| `bin/doGermlinePost.sh` | Run the germline reports |
| `bin/deliver.sh` | Deliver results to the next `r_NNN` folder (`-d` for the default path); writes as `svc_core001_bot01` via `dzdo` and fills the delivery email |
| `bin/deliverGermline.sh` | Deliver germline results, also as `svc_core001_bot01` |
| `bin/clean.sh` | Remove run outputs from the project folder |

### Config layering

Each run uses tempo's `iris` profile (`-profile iris`), then loads two
Nextflow config files:
1. `conf/iris.config` — cluster executor settings
2. `conf/tempo-{wgs|wes}-iris.config` — per-process resource overrides

The `conf/*juno*.config` files are dead (JUNO is shut down).

### Post-processing reports (`scripts/`)

All scripts run from the project directory (where `out/` lives). `doPost.sh`
runs the first six; `doGermlinePost.sh` runs the germline reports.

| Script | Output |
|--------|--------|
| `report01.R <ASSAY>` | Main somatic mutation Excel report |
| `qcReport01.R` | QC metrics report and FACETS QC report |
| `reportFacets01.R` | Copy number / Facets report |
| `reportSV01.R` | Somatic SV report (WGS only) |
| `getWGSStats.R` | WGS coverage stats (WGS only) |
| `reportAll.R` | Combined SV/SNV/CNV report (WGS only) |
| `reportGerm01.R` | Germline SNV report |
| `reportGermSV01.R` | Germline SV report (WGS only) |
| `reportTERT.R` | TERT mutations from the unfiltered MAFs (run by hand) |
| `nfTraceReport.R` | Nextflow trace analysis (runs automatically post-pipeline) |

Shared R utilities in `scripts/rsrc/`:
- `read_tempo_sv.R` — parses Tempo `.final.bedpe` SV files
- `add_sv_scores.R` — adds SV evidence scores
- `read_pairing.R` — reads the pairing file from the run logs
- `facets_rules.R` — the only definition of the FACETS sample rule
  (`|dipLogR| < 0.5`) and focal rule (segment <= 1 Mb); run
  `test_facets_rules.R` after changing it
- `xlsx_report.R` (openxlsx2), `xlsx_legacy.R` (openxlsx),
  `xlsx_defaults.R` — Excel writers and display defaults (zoom, window size)
- `nf-reports/` — trace parsing for `nfTraceReport.R`
- `cytoBand_hg19.txt.gz`, `centromeres_hg19.tsv` — reference tables

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
| IRIS | **`docs/IRIS_SLURM.md`** | verified 2026-07-18 against the live scheduler; sizes re-checked 2026-10-03 |
| JUNO | **`docs/JUNO_LSF.md`** | historical; cluster shut down 2026-10-01 |

IRIS facts are a snapshot and go stale without notice — re-verify via
`docs/IRIS_SLURM.md` section 8 rather than trusting remembered numbers.

Key rules, in full detail in those files:

- **IRIS has a 2-hour door.** `core001` is denied on the 7-day `cpu` partition,
  so the whole general pool is reachable only under a 2 h limit. Capacity cliffs:
  <= 2 h reaches **269** nodes, 2-3 h reaches **37**, > 3 h reaches **19**.
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
  IRIS caps retries at 2 (3 attempts), truncating JUNO's 4-attempt ramp
  (`maxRetries = 3`).

## Running the pipeline

### Environment setup

No setup step is required. The run scripts resolve `$CLUSTER` themselves,
export `NXF_OPTS`, `NXF_SINGULARITY_CACHEDIR`, `TMPDIR`, `WORKDIR`, and `PATH`
for the detected cluster, and pass `REFERENCE_BASE` to Tempo as
`--reference_base`. The IRIS paths are hardcoded under
`/scratch/core001/bic/socci`.

Each run gets a new `UUID` and runs Nextflow in
`WORKDIR=/scratch/core001/bic/socci/Adagio/$UUID/run`, not in the project
folder. Outputs go to `out/<PROJECT_ID>` in the project folder.

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

For `sbatch`, a `SLM/` folder must exist in the project folder (the
`#SBATCH -o` path), and the script must find its own location: plain `sbatch`
runs a spooled copy, so use the `~/bin/sbatch` wrapper or pass
`--export=SBATCH_SCRIPT_DIR=<adagio>/bin`.

Default WGS workflows: `snv,sv,qc,facets,mutsig`

### WES from FASTQs

```bash
bin/runTempoWESCohort.sh PROJECT_ID MAPPING.tsv PAIRING.tsv [AGGREGATE.tsv]
```

Default WES workflows: `snv,qc,facets`

Both scripts support `--workflows=W1,W2,...` to replace defaults and `--add-workflows=W3,...` to extend them. Available workflows: `snv, sv, mutsig, lohhla, facets, msisensor, germsnv, germsv, qc`.

### Post-processing

```bash
bin/doPost.sh          # somatic reports for the ASSAY_TYPE in the run log
bin/doGermlinePost.sh  # germline reports
```

### Resuming a failed run

Re-running a run script does not resume: it makes a new `UUID` and a new
`WORKDIR`, so Nextflow finds no cache. To resume, `cd` to the old `WORKDIR`
(the `WORKDIR:` line of `out/<PROJECT_ID>/runlog/cmd.sh.log`), export the same
environment the script sets, and rerun the `nextflow run ... -resume` command
logged in `cmd.sh.log`. See `README.md` for the steps. Trace, report and
timeline files are dated under `out/<PROJECT_ID>/pipeline_info/`, so no log
rotation is needed.

### Cleanup

```bash
bin/clean.sh   # removes out* work/ .nextflow.log* trace* report.html timeline.html fileTracking.tsv bamMapping.tsv
```

`clean.sh` works on the project folder only; it does not remove the scratch
`WORKDIR`.

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
cd adagio
bash 00.SETUP.sh   # installs Nextflow 25.10.4 (NXF_VER) into bin/
```

Keep Nextflow on 25.x: the IRIS retry logic uses `task.previousTrace.realtime`.
