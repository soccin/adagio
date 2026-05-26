# Adagio v3.1 Change Report

Changes from v3.0.0 (2026-03-14) to v3.1.0 (2026-05-26).

---

## Overview

v3.1.0 is a minor bump on the **Cordelia** line. The tempo submodule has not
moved — it remains at commit `8e6312e0`, branch `ccs/update-250925`, tag
`cordelia-01`. This release focuses on **SLURM resource optimization for the
IRIS cluster** based on observed walltime characteristics for the WES
pipeline, and ships a small set of unrelated improvements: SV evidence
scoring, a single-sample report fix, an opt-in `--anonymize` flag for WES,
and infrastructure housekeeping.

WGS-iris tier-ladder parity (porting the same queue/time logic to
`conf/tempo-wgs-iris.config`) is **deferred** to a future release.

---

## 1. IRIS SLURM optimization (the headline story)

### Problem

Pre-v3.1, every IRIS WES task was submitted to `cmobic_cpu` (167h walltime)
regardless of how long it was actually going to run. In practice the
majority of WES tasks finish well under the 2h `cpushort` limit, so this
default cost queue priority and slowed turnaround for jobs that would have
been eligible for short queues.

### The tier ladder

A reusable tiered queue/time picker is now defined at the top of
`conf/tempo-wes-iris.config`:

```groovy
def shortMediumLongLadder = [
    [queue: 'cpushort,cmobic_short', time: 2.h  ],
    [queue: 'cmobic_short',          time: 3.h  ],
    [queue: 'cmobic_cpu',            time: 167.h],
]

def queueFor = { task, ladder -> ladder[ tierFor(task, ladder) ].queue }
def timeFor  = { task, ladder -> ladder[ tierFor(task, ladder) ].time  }
```

`tierFor(task, ladder)` decides which tier a given attempt lands on:

| Condition | Tier |
|---|---|
| `task.attempt == 1` | `ladder[0]` (shortest) |
| retry, previous run hit walltime | step one tier up (clamped to last) |
| retry, previous run was non-wall (OOM/transient) | stay in current tier |

"Walltime hit" is defined as
`task.previousTrace.realtime >= (prev tier's time - 5min)`. The 5-minute
safety margin guards against jobs that timed out at exactly the cap.
`task.previousTrace.realtime` is in milliseconds (Nextflow 25.x); a missing
trace is defensively treated as `MAX` to force escalation.

### Short-queue-first default

For most processes that don't need the AlignReads-specific ladder, a
simpler short-or-long pattern is applied at the `process { ... }` default:

```groovy
queue = { ( task.attempt == 1 || (task.previousTrace?.realtime ?: Long.MAX_VALUE) < 6_900_000 ) ? 'cpushort,cmobic_short' : 'cmobic_cpu' }
time  = { ( task.attempt == 1 || (task.previousTrace?.realtime ?: Long.MAX_VALUE) < 6_900_000 ) ? 2.h : (task.attempt < 4 ? 48.h * (task.attempt - 1) : 167.h) }
```

The `6_900_000 ms = 1h55m` threshold treats any retry whose previous attempt
ran < 1h55m as a non-walltime failure (OOM, transient, etc.) and keeps it
in the short queue. Otherwise the job escalates to `cmobic_cpu` with the
original time ramp shifted one attempt to the left.

### AlignReads — dedicated tier ladder

Observed maximum AlignReads walltime is ~2.14h — just past the 2h
`cpushort` cap but well inside the 3h `cmobic_short` cap. A jump straight
to `cmobic_cpu` would be wasteful, so AlignReads uses the short→medium→long
ladder defined above (2h → 3h → 167h) so a walltime hit steps tier-by-tier:

```groovy
withName:AlignReads {
    cpus   = { 4 + 4 * task.attempt }
    memory = { 15.GB }
    queue  = { queueFor(task, shortMediumLongLadder) }
    time   = { timeFor (task, shortMediumLongLadder) }
}
```

CPU base for AlignReads was also reduced from `8 + 8*attempt` to
`4 + 4*attempt` based on observed parallelization.

### Per-process time overrides

Long-running callers (SvABA, Delly, Neoantigen, RunSV/Manta/Strelka2,
LOHHLA, MultiQC, etc.) all received the short-queue-first pattern with
caller-appropriate long-queue fallbacks. The full set of `withName` /
`withLabel` blocks in `conf/tempo-wes-iris.config` was updated.

### Retry strategy

`conf/iris.config` now sets, at the `process` block level:

```groovy
maxRetries    = 2
errorStrategy = { task.attempt <= process.maxRetries ? 'retry' : 'ignore' }
```

This gives every process two retries (three total attempts) before being
marked ignored, which combined with the tier ladder gives a natural escalation
path.

### New: GermlineRunHaplotypecaller resource entry

`GermlineRunHaplotypecaller` was previously falling through to default
allocations. It now has an explicit `cpus = 2` / `memory = 5.GB * attempt`
entry (`9eb147b`).

---

## 2. Run scripts

### `runTempoWESCohort.sh` — opt-in anonymize

Pre-v3.1, `--anonymizeFQ` was always passed to Tempo, stripping read IDs
from every WES run. This was unwanted as a default. v3.1 introduces a new
`--anonymize` CLI flag:

```bash
bin/runTempoWESCohort.sh --anonymize PROJECT_ID MAPPING.tsv PAIRING.tsv
```

Default is **off**. Implementation builds `NF_PARAMS` conditionally so an
empty string is never passed to nextflow. WGS is unaffected — it starts
from BAMs, so `--anonymizeFQ` has no meaning there. (`6bcad83`, `ac1284e`)

### Partition cleanup

The defunct `cmobic_pipeline` partition has been removed everywhere it
appeared:

- `bin/runTempoWESCohort.sh` SBATCH header: now `bic_devs,cmobic_cpu`
- `bin/runTempoWGSBam.sh` SBATCH header: now `cmobic_cpu,bic_devs`
- `scripts/downSampleBam.sh` SBATCH header: now `cmobic_cpu`
- `conf/iris.config` `process.queue` line removed (queue is set per-process
  via the tier logic now)

A short-lived rename of `cmobic_pipeline` to `cmobic_short` was reverted
before merge (`d1b4c70` → `3914503` → `445e1e3`).

---

## 3. Reporting

### SV scoring (`scripts/reportSV01.R`, new `scripts/rsrc/add_sv_scores.R`)

The SV report (v6) now includes evidence scores derived from the max ALT
read-supporting count across MANTA, DELLY, SVABA:

| Column | Meaning |
|---|---|
| `SCORE_SPAN`  | max of paired-end/discordant ALT (`manta_PR` ALT, `delly_DV`, `svaba_DR`) |
| `SCORE_SPLIT` | max of split/junction ALT (`manta_SR` ALT, `delly_RV`, `svaba_SR`) |
| `SCORE`       | `max(SCORE_SPAN, SCORE_SPLIT)` |

Rows are sorted by descending `SCORE` so the highest-confidence events are
at the top of the sheet. Implementation lives in
`scripts/rsrc/add_sv_scores.R`. (`bbd21c3`, `0098d3a`)

### `svColTypeDescriptions.csv` rewrite

The column-description CSV used by the SV report has been rewritten from
scratch. It previously described raw VCF INFO fields from BRASS/DELLY/MANTA/
SVABA — fields that don't appear in the actual report. The new file
describes the columns that do appear: gene/site annotations, VAFs, ALT
read counts, callers, and the new SCORE columns. (`ac5e15f`)

### SvABA VAF cap (`scripts/reportSV01.R`)

Tumor and normal SvABA VAFs are now capped at 1.0 using `pmin`:

```r
t_svaba_VAF = pmin(t_svaba_AD / t_svaba_DP, 1)
n_svaba_VAF = pmin(n_svaba_AD / n_svaba_DP, 1)
```

This handles edge cases where SvABA's allele depth slightly exceeds its
reported depth-of-coverage. (`6d30e1d`)

### Single-sample Gene Stats fix (`scripts/report01.R`)

The "Gene Stats" sheet shows cross-sample mutation frequencies and is
meaningless for single-sample runs. The sheet is now skipped when
`nSamples == 1`. The sheet-indexing was also rewritten to address sheets
by name (`writeDataTable(wb, sheet="Mutations", ...)`) instead of by
numeric index, since the Gene Stats sheet may or may not be present.
(`5819c87`)

---

## 4. Infrastructure / housekeeping

- **Nextflow pinned** to `25.10.4` in `00.SETUP.sh` via
  `export NXF_VER=25.10.4` before the installer runs. (`ae330e7`)
- **`CLAUDE.md`** added at the repo root to give AI assistants codebase
  context (architecture, entry points, config layering, post-processing
  scripts, run instructions). (`2065799`)
- **`bin/.gitignore`** added to keep editor swap/backup files
  (`*.swp`, `*~`, etc.) out of commits. (`ecbc6a0`)

---

## 5. Files changed

| Area | Files |
|---|---|
| Run scripts | `bin/runTempoWESCohort.sh`, `bin/runTempoWGSBam.sh` |
| Cluster config | `conf/iris.config`, `conf/tempo-wes-iris.config` |
| Reporting | `scripts/report01.R`, `scripts/reportSV01.R`, `scripts/rsrc/add_sv_scores.R` (new), `scripts/rsrc/svColTypeDescriptions.csv` |
| Utilities | `scripts/downSampleBam.sh` |
| Setup / repo | `00.SETUP.sh`, `bin/.gitignore` (new), `CLAUDE.md` (new) |
| Release docs | `VERSION.md`, `README.md`, `CHANGELOG.md`, `docs/releases/CHANGE_REPORT_v3.1.md` (new) |

---

## 6. Tempo submodule

**Unchanged.** Still at commit `8e6312e0`, branch `ccs/update-250925`, tag
`cordelia-01` (forked 2025-10-06). This release is metadata + adagio-side
configuration only; no upstream tempo pipeline changes.

---

## 7. Deferred to a future release

- **WGS-iris tier-ladder parity.** `conf/tempo-wgs-iris.config` still uses
  the pre-v3.1 `task.attempt`-based time ramp
  (`time = { task.attempt < 3 ? 48.h * task.attempt : 167.h }`) and does
  not benefit from the short-queue-first pattern. Porting the
  `queueFor`/`timeFor` helpers and the short-or-long retry logic to WGS
  will be the focus of a future release.
