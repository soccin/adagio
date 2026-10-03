# Adagio v3.2.1 Change Report

Changes from v3.1.0 (2026-05-26) to v3.2.1 (2026-10-02).

---

## Overview

v3.2.1 is a minor bump on the **Cordelia** line. It collects four months of
work that accumulated on `master` and `devs/iris` without a release: 60
non-merge commits touching 44 files, not counting the release
documentation commits, plus a tempo submodule move from `8e6312e0` to
`a7ecd35a` (branch `ccs/update-250925` to `devs/iris`, 7 commits).

It is the first release after JUNO was shut down for good on 2026-10-01.
IRIS is the only supported cluster.

The number skips 3.2.0. A `v3.2.0-beta` tag was placed on `devs/iris` at
`3a7a77e` on 2026-09-07 and never released; everything under it is in this
release, and 3.2.1 supersedes it.

Headline items:

1. **WGS IRIS tier-ladder parity**, the item deferred from v3.1.0. The WGS
   config now has the same short-queue-first default, `shortMediumLongLadder`
   and `tierFor`/`queueFor`/`timeFor` helpers as WES.
2. **Measured SV caller sizing on IRIS.** Delly and SvABA moved from estimates
   to values derived from 811 and 162 completed tasks, ending in a two-rung,
   two-attempt ladder that handles the normal and damaged-FFPE library
   populations separately.
3. **Per-task SLURM QoS.** A `qosFor` picker and `unset SBATCH_QOS` in the
   drivers fix a bug where every short-queue submission was rejected and
   `cpushort` was never actually used.
4. **Tempo: ENCODE blacklists for SvABA and Delly**, `svaba -p` matched to
   `task.cpus`, and an opt-in `skipQualimap` parameter.
5. **Reporting:** TERT promoter rescue and FACETS dipLogR in the main report,
   a focal-gene copy-number sheet in the FACETS report, SV report v8 with a
   recurrent gene-pair sheet and styled workbooks, and a shared-normal fix in
   the WGS stats plots.
6. **Delivery and tooling on IRIS:** `deliver.sh` delivers locally on IRIS
   with automatic `r_NNN`, a `makeTempoBams.sh` alignment-only runner, pairing
   file builders, SV BAM filters, and mail on driver END or FAIL.
7. **Policy:** JUNO was frozen ahead of its shutdown and was shut down on
   2026-10-01. Its code paths are dead and left in place for a later
   release to remove. Cluster references `docs/IRIS_SLURM.md` and
   `docs/JUNO_LSF.md` added.

Not in this release: the WES config right-sizing identified in
`devs/wes-iris-parity-report.md` (see section 8), and a fix for the
CohortRunMultiQC failure on BAM-input WGS runs (section 7).

---

## 1. IRIS WGS SLURM configuration (`conf/tempo-wgs-iris.config`)

This file received 382 lines of change. The end state is described here;
the intermediate commits are listed where the history matters.

### 1a. Tier-ladder parity with WES (`448660c`, 2026-06-09)

The WES tier picker from v3.1.0 was ported verbatim:

- Process-level default: attempt 1 submits to `cpushort,cmobic_short` with a
  2h cap. On retry, if the previous attempt ran under 1h55m
  (`6_900_000` ms) the failure was not a walltime hit and the task stays in
  the short queues; otherwise it escalates to `cmobic_cpu` with the original
  time ramp shifted one attempt left.
- `shortMediumLongLadder` (2h / 3h / 167h) with `tierFor`, `queueFor`,
  `timeFor`, applied to `AlignReads` (cpus stay WGS-specific at
  `16 + 8 * attempt`).
- The `meta.size > 100 ? maxWallTime : minWallTime` logic on the GATK4SPARK
  mark-duplicates, set-tags, BQSR, apply-BQSR and merge-BAM processes was
  dropped. This also removes the dependency on `params.minWallTime`, which
  TODO item 8 had flagged as coming in only through tempo's juno profile.

### 1b. Right-sizing from traces (`bff362a`, 2026-06-09)

| Process | Before | v3.2.1 |
|---|---|---|
| `QcQualimap` | `4 * attempt` cpus, `128.GB + 128.GB * attempt` | `attempt <= 2 ? 4 : 8` cpus, flat 20 GB, explicit `--mem` of `cpus * 20 * 1.1` GB |
| `DoFacets` | `4 + 12 * attempt` cpus, `246.GB * attempt` | `attempt <= 2 ? 2 : 4` cpus, 64 GB then 128 GB |

The QcQualimap `clusterOptions` override matters because tempo's module
computes `availMem = cpus * memory` and sizes the JVM heap from it. The
explicit `--mem` tells SLURM what the process will actually use.

### 1c. SV callers: Delly and SvABA

Six commits between July and August replaced the estimated settings for
`SomaticDellyCall` and `.*RunSvABA` with measured ones. In order:
`3d2dc01` (Delly from 565 tasks), `6951659` (both callers from 1,136 tasks,
own time ladders), `3328bb0` (memory-only probe for damaged libraries),
`1e207f2` (fast-fail third attempt), `9a86294` (max out attempt 1, since the
small attempt was always killed), `7d4d466` (final two-rung design).

End state:

```groovy
def rungFor = { task, ladder -> ladder[ Math.min( task.attempt - 1, ladder.size() - 1 ) ] }

def dellyLadder = [
    [queue: 'cmobic_cpu', time:  11.h, memory:  32.GB],
    [queue: 'cmobic_cpu', time: 167.h, memory: 320.GB],
]
def svabaLadder = [
    [queue: 'cmobic_cpu', time:   6.h, memory:  48.GB],
    [queue: 'cmobic_cpu', time: 167.h, memory: 320.GB],
]

withName: SomaticDellyCall { cpus = { 2 };  memory/queue/time from dellyLadder; errorStrategy = one retry }
withName: '.*RunSvABA'    { cpus = { 42 }; memory/queue/time from svabaLadder; errorStrategy = one retry }
```

Why it looks like this:

- Neither caller has ever finished inside 3h (fastest 4.30h and 3.23h), so
  both pin `cmobic_cpu` on every attempt. The explicit `queue` is required;
  without it the block inherits the short-queue default and attempt 1 is a
  guaranteed 2h walltime kill.
- Both callers are bimodal in time and memory, and the two modes are the
  same two library populations. A normal library finishes on rung 1. A
  damaged FFPE library (for example APTL_00036_T01) OOMs at 32 GB within
  about 35 minutes and needs 256 GB plus days of runtime; only rung 2 can
  finish it. Intermediate rungs only burned attempts.
- The rung is chosen by `task.attempt`, not by `tierFor`. `tierFor` promotes
  only after a walltime kill, and an OOM at 35 minutes is not one, so it
  would hand attempt 2 the same memory that just failed.
- `errorStrategy` on both processes allows exactly one retry, overriding
  `maxRetries = 2` from `conf/iris.config`.
- Delly cpus 3 to 2: it runs at 99.9% of one core regardless. On
  `cmobic_cpu` that raises concurrent slots from 412 to 632. Attempt-1 memory
  must stay at 32 GB (peak RSS p99 18.0 GB, max 22.6 GB); raising it makes
  memory rather than cores the binding constraint and halves concurrency.
- SvABA runs at 94 to 98% of every core it is given, so memory tracks
  thread count. 48 GB is 1.9x the extrapolated peak at 42 cpus. At 42 cpus
  one task fits per 56-core node whatever the memory, so rung 1 memory buys
  scheduling latency rather than throughput.

The file carries long comment blocks recording the measurements behind
each number. Read them before changing anything.

### 1d. Per-task QoS (`0a3e020`, 2026-09-27)

`cpushort` allows only QoS `normal`, and a multi-partition request carrying
`priority` is rejected with `Invalid qos specification`. With
`SBATCH_QOS=priority` exported in the launching shell, every task sent to
`cpushort,cmobic_short` was rejected at submit time. Nextflow reported
"Error submitting process", the retry escalated to `cmobic_cpu`, so
`cpushort` was never used and each short task lost an attempt.

Fix, in both IRIS configs and all three SBATCH drivers:

```groovy
def qosFor = { task -> task.queue?.contains('cpushort') ? '' : '--qos=priority' }

process {
  clusterOptions = { qosFor(task) }
  ...
}
```

- Any `withName` block that sets its own `clusterOptions` must append
  `qosFor(task)` itself. `QcQualimap` does.
- `bin/runTempoWGSBam.sh`, `bin/runTempoWESCohort.sh`, `bin/makeTempoBams.sh`
  run `unset SBATCH_QOS` on IRIS, because `sbatch` lets the environment
  override `#SBATCH` lines, which is where Nextflow writes `clusterOptions`.
- The driver job itself submits to `cmobic_cpu` only with
  `#SBATCH --qos=priority`. `bic_devs` allows only QoS `normal` and cannot
  be listed alongside a priority request.
- `docs/IRIS_SLURM.md` records the restriction.

Tested on IRIS: a default-queue task ran on `cpushort` with QoS `normal`;
a `SomaticDellyCall` task ran on `cmobic_cpu` with QoS `priority`.

### 1e. AnnotateSVBedpe memory (`8b7056b`, `c000f27`)

`.*AnnotateSVBedpe` (somatic and germline) had no IRIS rule and fell
through to tempo's JUNO genome defaults at 8 GB. On Proj_16840_P
`bedtools pairtopair` was OOM-killed at that limit, and a bare `except:` in
`filter_regions_bedpe.py` turned the failure into "zero overlaps, exit 0".
The delivered report contained 17 unfiltered foldback artifacts.

New rule: `memory = { 32.GB * task.attempt }`. Attempt 1 is the whole fix.
The silent failure exits 0, so Nextflow never retries it and the ramp only
helps when the cgroup kills the step outright. The durable fix is a loud
failure in the Python filter, which lives in the `iannotatesv` container
(section 7).

### 1f. Qualimap: what happened and what ships

On 2026-09-05 `devs/iris` set `skipQualimap = true` in the WGS params and
pinned `QcQualimap` to `cmobic_cpu` at 30h then 167h with flat 4 cpus
(`44e88f7`), after bamqc took 19 to 25h per sample and OOMed on the deepest
BAMs in one project. Skipping bamqc drops the Coverage, % Aligned, Error
rate and Insert size columns from the sample and somatic MultiQC reports,
and the % Aligned criterion silently leaves QC status.

Proj_18645_C ran on `master` on 2026-09-29 and completed bamqc with the
section 1b settings (4/8 cpus, 20 GB, explicit `--mem`). v3.2.1 therefore
ships `master`'s block and does not set `skipQualimap`. The parameter
remains in tempo (default `false`) as an opt-in for a future run that needs
it. The tempo change that halved bamqc's thread count from `cpus * 2` to
`cpus` is shared code and is in effect (section 2).

### 1g. The one WES config change (`b827cd5`, `0a3e020`)

`conf/tempo-wes-iris.config` gained `qosFor` (section 1d) and a retuned
`GermlineRunHaplotypecaller`: `2 * attempt` cpus, `8.GB * attempt`, on
`shortMediumLongLadder`. Nothing else in the WES config changed; see
section 8 for what is pending there.

---

## 2. Tempo submodule (`8e6312e0` to `a7ecd35a`)

`.gitmodules` now tracks branch `devs/iris` (was `eos-devs`, then
`ccs/update-250925` from `b7ed402`). The pinned commit is on
`origin/devs/iris` and resolves from a fresh clone. `git describe` reports
`cordelia-01-9-ga7ecd35a`; the `cordelia-02` tag mentioned in `e7e8ac3` was
local to another checkout and is not present here.

Seven tempo commits, all by this project (full detail in `CHANGELOG_TEMPO.md`):

| Tempo commit | Change |
|---|---|
| `49773e01` | `svaba -p` matches `task.cpus` (was `cpus * 2`; the cgroup capped it anyway, so the doubled threads only cost memory) |
| `e591a3e8` | SvABA `-B` ENCODE blacklist |
| `356fa8db` | Delly uses the adagio ENCODE exclude file |
| `2ff7e96a` | Docs for the above |
| `ed83b1b0` | Merge of the SV commits into `ccs/update-250925` |
| `d83b4150` | `params.skipQualimap` (default `false`); bamqc `-nt` from `cpus * 2` to `cpus` |
| `a7ecd35a` | Merge of `d83b4150` into `devs/iris` |

**New runtime dependency.** Both SV region files resolve through
`${projectDir}/../rsrc/` and `defineReferenceMap` validates them at startup
with `checkIfExists`. Tempo now requires its parent adagio checkout for
every run, not only for SV workflows. The files are tracked in adagio:

| File | Commit |
|---|---|
| `rsrc/genomic/hg19/adagio_SvABA_BlackList_b37.v1.bed` | `65537b0` |
| `rsrc/genomic/hg19/encode-blacklist.b37.v2.bed` | `65537b0` |
| `rsrc/genomic/hg19/encode-blacklist.b37.v2.excl.tsv` | `65537b0` |
| `rsrc/genomic/hg19/encode-blacklist.b37.v2.CLEAN.bed` | `03f8371` |

---

## 3. Run scripts and pipeline tooling

### Drivers (`bin/runTempoWGSBam.sh`, `bin/runTempoWESCohort.sh`)

- `#SBATCH --mail-user` and `--mail-type=END,FAIL` on every script with an
  SBATCH header, including `bin/makeTempoBams.sh` and
  `scripts/downSampleBam.sh`. One message per job, on whichever of the two
  happens. (`3a7a77e`, `f0bf595`)
- Driver partition `cmobic_cpu` only, `--qos=priority`, `unset SBATCH_QOS`
  on IRIS (section 1d).
- `SETENVRC` removed; the run scripts already export every cluster
  variable. `bin/clean.sh` replaces the old `clean` alias. (`dd3b237`)

### New: `bin/makeTempoBams.sh` (`2260b32`)

Alignment-only runner. Builds BQSR BAMs from FASTQs through tempo with no
pairing or variant calling, supports `--assay`, `--qc`, `--anonymize`, and
writes `out/$PROJECT_ID` BAMs plus a `bamMapping.tsv` ready for
`runTempoWGSBam.sh`.

### Delivery (`bin/deliver.sh`)

Reworked in three steps: deliver over ssh with an automatic `r_NNN`
(`d11584d`, early-exit fix `8ab4ecc`), skip the BIC toolchain steps on IRIS
and deliver `Map/` mapping data (`9036246`), then deliver locally on IRIS
paths (`bd2016f`). End state on IRIS:

- `-d|--default` derives `aa/bbb/Proj_nnnnn` from the current
  `.../Users/Aa/BBB/Proj_nnnnn` path under
  `/data1/core002/res/bic/results`.
- `r_NNN` increments from the existing local folders.
- `rsync` into the target, mapping kept under the delivery folder,
  `project.yaml` written by the new `bin/readme2yaml.R` (`c4230d1`), which
  parses `README.txt` for PI, investigator, genome and path fields.

### Pairing and input helpers

- `scripts/pair_samples.R` (`f40bb46`): tumor-normal pairing TSV from
  mapping files by patient and N/T suffix.
- `bin/make_pairing_draft.py` (`24c7eb8`): regex-driven pairing from a
  tempo mapping file, `-u/--unmatched` for tumors without a normal, one row
  per normal when a patient has several, unpaired normals reported on
  stderr.
- `scripts/fastq2tempo.R` usage now documents each input file layout
  (`4c7c25a`).

### SV BAM filters (`scripts/bamFilters/`, `f6b9afa`, `b07141c`)

`filter_sv_bam.py` and `filter_sv_bam.sh` strip duplicates, QC-fail,
secondary and both-unmapped reads while keeping supplementary and
one-end-anchored reads, write indexed `*.flt.bam`, and warn if no
duplicate flags are seen. Optional `-v` progress bar.

### Setup

`00.SETUP.sh` prints a reminder to clone and run wgsTriage after installing
Nextflow (`ddef784`). Nothing is cloned automatically.

---

## 4. Reporting (`scripts/`)

### Main somatic report (`report01.R`)

- **TERT promoter rescue** (`095c40a`, `be57ad1`, `d12d3e0`). `mafToReportTbl()`
  is extracted and non-PASS TERT 5'Flank variants from the per-pair
  unfiltered MAFs are appended to the Mutations sheet. The Gene Stats sheet
  counts them; sample mutation totals do not. Column types are copied from
  the filtered table so a run with zero rescued rows still binds.
- **FACETS dipLogR** joined next to `facets_qc`, two decimals (`251907a`).
- `reportTERT.R` reads MAFs as text and restores types afterwards, fixing a
  `bind_rows` failure on mixed per-file column types (`1736723`).

### FACETS report (`reportFacets01.R`, output now `*_facets_v4.xlsx`)

- `--keep-failed` disables the QC filter; outputs are tagged `_NO_FILT`
  (`ba7f7d9`). `--help` works from any directory (`e1aa3e9`).
- Sample keep rule: passed FACETS QC, or `|dipLogR| < 0.5`. Missing dipLogR
  does not rescue a QC failure (`c96af41`).
- **`geneLevelFocal` sheet** replaces `geneLevel` (`357f377`): genes on
  segments of 1 Mb or less whose non-diploid focal calls are all gains or
  all losses, with cohort CN percentages and chromosome arm from
  `scripts/rsrc/centromeres_hg19.tsv`. Autosomes only. Documented in
  `docs/DESCRIPTION_FOCAL_GENES.md` (reader guide) and
  `docs/METHODS_CNV_GENES.md` (selection rules and checks) (`fb91f2b`).

### SV report (`reportSV01.R`, now v8)

- `SVFreq` sheet of gene pairs hit in more than one sample, with an
  orientation-independent pair label (`555f6fb`, v6 to v7). `NumSVs`
  zero-filled for tumors with no BEDPE.
- Workbooks written through openxlsx2 with bold frozen headers, fitted
  widths and per-column number formats; non-finite values become empty
  cells (`b5fb3ca`, v7 to v8).

### Pairing from run logs (`scripts/rsrc/read_pairing.R`, `a70b55b`)

`read_pairing()` resolves the pairing file from `out/**/runlog/cmd.sh.log`,
preferring the copied runlog TSV. Used by `getWGSStats.R` and `reportSV01.R`
instead of filename discovery.

### WGS stats (`getWGSStats.R`)

- A normal paired with several tumors was replicated once per pair in the
  plots, stacking to impossible values such as 400% aligned in pairs.
  `distinct()` after the gather fixes it; the Excel table was never affected
  (`1fbe681`).
- Metrics under `tests/fixtures` (tool checkouts such as wgsTriage) are no
  longer read as samples; the directory walk now actually recurses
  (`0cf00e8`).

### Trace report (`nfTraceReport.R`)

Timestamped progress to stderr at each stage, keeping stdout clean for the
piped Markdown (`8a118d4`).

---

## 5. Documentation and policy

- **`docs/IRIS_SLURM.md`** (`87069a5`): what account `core001` can submit
  to, the 2-hour `cpushort`/`cpu` access boundary (270 nodes under 2h, 37
  under 3h, 19 above), hard CPU and memory caps, QoS limits, how to tell a
  walltime kill from an OOM, and the exact `sinfo`/`scontrol`/`sacctmgr`
  commands to re-verify each fact.
- **`docs/JUNO_LSF.md`** (`2e7ade3`): config-derived reference for LSF on
  JUNO and the three traps when porting settings to IRIS (time, memory
  semantics, retry count).
- **`CLAUDE.md`**: HPC clusters section with the rules above; JUNO freeze
  (`4b3dd47`), updated at release: JUNO was shut down on 2026-10-01, IRIS
  is the only supported cluster, and the JUNO configs and code paths are
  dead but left in place. It also records that tempo's `iris` profile
  loads `tempo/conf/juno.config` and the `resources_juno*.config` files,
  so those must survive the JUNO removal.
- **`devs/wes-iris-parity-report.md`** (`0cb8afb`): every WGS IRIS config
  change since 2026-05-25 mapped onto the WES equivalents, backed by
  27,014 completed WES tasks. This is the work plan for the next release.
- **`bugs/`**: three archived reports (section 7).
- `TODO.md` (`ba6fbc2`) lists post-v3.1.0 items; status at this release is
  recorded at the top of that file.

---

## 6. Files changed

| Area | Files |
|---|---|
| Cluster config | `conf/tempo-wgs-iris.config`, `conf/tempo-wes-iris.config` |
| Run scripts | `bin/runTempoWGSBam.sh`, `bin/runTempoWESCohort.sh`, `bin/makeTempoBams.sh` (new), `bin/clean.sh` (new), `bin/deliver.sh`, `bin/readme2yaml.R` (new), `bin/make_pairing_draft.py` (new), `SETENVRC` (removed), `00.SETUP.sh` |
| Reporting | `scripts/report01.R`, `scripts/reportTERT.R`, `scripts/reportFacets01.R`, `scripts/reportSV01.R`, `scripts/getWGSStats.R`, `scripts/nfTraceReport.R`, `scripts/fastq2tempo.R`, `scripts/pair_samples.R` (new), `scripts/rsrc/read_pairing.R` (new), `scripts/rsrc/centromeres_hg19.tsv` (new) |
| Utilities | `scripts/bamFilters/filter_sv_bam.py` (new), `scripts/bamFilters/filter_sv_bam.sh` (new), `scripts/downSampleBam.sh` |
| Reference data | `rsrc/genomic/hg19/` (4 new files) |
| Docs | `docs/IRIS_SLURM.md`, `docs/JUNO_LSF.md`, `docs/DESCRIPTION_FOCAL_GENES.md`, `docs/METHODS_CNV_GENES.md`, `devs/wes-iris-parity-report.md`, `bugs/` (3 reports), `CLAUDE.md`, `TODO.md`, `00.FIXME.txt` |
| Submodule | `tempo` (`8e6312e0` to `a7ecd35a`), `.gitmodules` |
| Release docs | `VERSION.md`, `README.md`, `CHANGELOG.md`, `CHANGELOG_TEMPO.md`, `docs/releases/CHANGE_REPORT_v3.2.1.md` (new) |

---

## 7. Known issues open at release

- **CohortRunMultiQC fails on BAM-input WGS runs** (exit 1, error ignored),
  so the cohort MultiQC report is missing from `out/`. Root cause in
  `bugs/BUG_REPORT_CohortRunMultiQC.md`: `<sample>.recal.bam` naming doubles
  the Qualimap rows, no fastp files drops `max_table_rows`, MultiQC 1.9
  renders a beeswarm and never writes `multiqc_general_stats.txt`, and
  `general_stats_parse.py` crashes. Pointer in `00.FIXME.txt`.
- **`filter_regions_bedpe.py` fails silently on OOM** (section 1e). The
  32 GB request avoids the observed case; the script needs a loud failure,
  which means rebuilding the `iannotatesv` container.
- **ClusterSV crash** on a geometry invariant in
  `intra_vs_single_intra_p_value()`, deterministic across retries, with a
  reproducing BEDPE in `bugs/BUG_REPORT_ClusterSV.zip`. Defect in ClusterSV,
  not in the pipeline input.
- **SvABA integration review items** parked in `bugs/BUG_REPORT_SvABA.md`:
  merge threshold flip with a third caller, missing test-profile guard,
  unanchored germline `rm` glob, germline unfiltered VCF publish.
- **WGS driver runs the trace report in the work directory.**
  `bin/runTempoWGSBam.sh` does `cd $WORKDIR` and never returns before
  `nfTraceReport.R`, so `RUN_REPORT_*.md` lands under `work/`. The WES driver
  uses `pushd`/`popd` and is correct.
- The `cordelia-02` tag referenced in `e7e8ac3` does not exist in this
  tempo clone (section 2).

---

## 8. Deferred to the next release

The WES IRIS config was not changed beyond sections 1d and 1g. The parity
report (`devs/wes-iris-parity-report.md`) lists, with measurements:

- `QcQualimap` on WES still uses `4 * attempt` cpus and
  `128.GB + 128.GB * attempt`, which hands the JVM a 768 GB heap against a
  256 GB request and OOM-killed 79 of 238 tasks in one run. Port the WGS
  block from section 1b.
- `DoFacets` right-sizing (2 cpus, 16 GB then 32 GB).
- Ten blanket `4 + 12 * attempt` cpu / `246.GB * attempt` blocks whose WES
  tasks use under 5 GB.
- Do not port the Delly/SvABA ladders; WES does not run the SV workflow by
  default.

Remove the dead JUNO code paths: `conf/*juno*.config`, the `JUNO`
branches in the `bin/` drivers and cluster detection, and the `JUNO` case
in `scripts/report01.R`. Keep the tempo-side `juno` config files that the
`iris` profile loads (section 5).

Also open: a replacement for bamqc on deep WGS BAMs, the stale version stamp
in `conf/iris.config`, hardcoded `/scratch/core001/bic/socci` paths in the
drivers, and the `SLM/` pre-creation requirement. See `TODO.md`.

---

## 9. Upgrade notes

- IRIS only. JUNO was shut down on 2026-10-01; the JUNO configs and
  driver branches are still present but unmaintained and untested.
- Clone or update with submodules: `git submodule update --init`. The
  pinned tempo commit is on `origin/devs/iris`.
- Tempo now reads `rsrc/genomic/hg19/` from the adagio checkout on every
  run (section 2). A tempo checkout outside adagio will fail at startup.
- Nextflow stays pinned to `25.10.4` in `00.SETUP.sh`. The retry logic
  depends on `task.previousTrace.realtime`, which needs Nextflow 25.x.
- Do not export `SBATCH_QOS` when launching; the drivers unset it on IRIS
  anyway (section 1d).
- `SETENVRC` is gone. Nothing needs to be sourced before running the
  drivers.
- SV report output is now `*_SV_Report01_v8.xlsx`; FACETS report output is
  `*_facets_v4.xlsx`.
