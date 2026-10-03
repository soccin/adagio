# Adagio TODO

Items to address after v3.1.0. Ordered by impact, not effort.

## Status at v3.2.2 (2026-10-03)

| Item | Status |
|---|---|
| 1. WGS-iris tier-ladder parity | Done, `448660c`. Delly/SvABA use their own two-rung ladders (`7d4d466`), by design. |
| 2. Shared tier-ladder helpers | Open. Helpers are duplicated in both IRIS configs. |
| 3. Stale comments and version markers | Open. `conf/iris.config` still says `v2.3.7`; `conf/tempo-wgs-iris.config` still says "hard coded with IRIS specific limits" (WES fixed in `6f7fdbe`). |
| 4. Hardcoded user paths | Open. |
| 5. `SLM/` pre-creation | Open. |
| 6. Fate of `rel/*` branches | Open. `rel/v3.1.0` still on origin; `rel/v3.2.1` was not kept; `rel/v3.2.2` is the current release branch. |
| 7. Tier-logic smoke test | Partly. QoS fix was tested live on IRIS (`0a3e020`); no scripted test. |
| 8. `params.minWallTime` provenance | Done. `448660c` removed the `meta.size` time logic that used it. |
| 9. `nfTraceReport.R` failure modes | Open. New: the WGS driver runs it from the scratch `$WORKDIR`, where there is no `out/`, so the WGS report fails. WES and `makeTempoBams.sh` use `pushd`/`popd`. |
| 10. Documentation drift | Mostly done in v3.2.2: README and `CLAUDE.md` resume and cleanup steps rewritten for IRIS, Nextflow pin in `docs/install.md`. `scripts/resume00.sh` still has JUNO paths. |

Done in v3.2.2:

- WES IRIS config right-sizing per `devs/wes-iris-work-plan.md`:
  QcQualimap heap (OOM-killed 80 of 241 tasks), DoFacets, and the
  oversized blanket blocks (`250ae33`, `23bd930`, `6f7fdbe`). Still to
  do: watch the first WES run on v3.2.2 for exit 137 in QcQualimap,
  DoFacets and CohortRunMultiQC.

New since v3.1.0:

- CohortRunMultiQC fails on BAM-input WGS runs;
  `bugs/BUG_REPORT_CohortRunMultiQC.md`.
- `filter_regions_bedpe.py` bare `except` hides OOM as "zero overlaps";
  needs a loud failure and an `iannotatesv` container rebuild.
- Replacement for qualimap bamqc on deep WGS BAMs (19-25h per sample).
- Check the bamqc thread count on the first v3.2.1 WGS run. v3.2.1 pairs
  master's QcQualimap settings (4/8 cpus, 20GB, explicit `--mem`) with
  tempo `a7ecd35a`, which runs bamqc with `-nt = cpus` instead of
  `cpus * 2`. Proj_18645_C validated those settings on master's tempo
  (`ed83b1b0`, `-nt = cpus * 2`), and every `devs/iris` run skipped
  bamqc, so this combination has not run on IRIS. Low risk: fewer
  threads on the same cores should not slow it and may use less memory.
  Watch the first QcQualimap tasks for runtime and exit 137.
- Remove the dead JUNO code paths; JUNO was shut down for good on
  2026-10-01. Keep `tempo/conf/juno.config` and
  `tempo/conf/resources_juno*.config`: tempo's `iris` profile loads them.
- Tag the tempo pointer (`a7ecd35a`) so `VERSION.md` can cite a tag
  instead of `cordelia-01-9-ga7ecd35a`.

Found in the v3.2.2 release review (details in item 11):

- WGS `doPost.sh` aborts when there are no WGS metrics.
- `reportFacets01.R` can write `Proj_Proj_...` file names.
- `deliverGermline.sh` `readme2yaml.R` path and usage text.
- `runTempoWGSBam.sh` usage typo.

## 1. WGS-iris SLURM tier-ladder parity

`conf/tempo-wgs-iris.config` still uses the pre-v3.1 retry pattern
(`time = { task.attempt < 3 ? 48.h * task.attempt : 167.h }`) and the
pre-existing `task.time = { meta.size > 100 ? params.maxWallTime : params.minWallTime }`
shape on GATK4SPARK / BQSR / merge processes. It does not benefit from
short-queue-first or the `shortMediumLongLadder` introduced for WES.

- Port `queueFor` / `timeFor` helpers and `shortMediumLongLadder` from
  `conf/tempo-wes-iris.config` (consider hoisting them into a shared
  include file rather than copy-pasting — both configs would then share
  the same tier picker).
- Apply the short-queue-first pattern (`cpushort,cmobic_short` @ 2h →
  `cmobic_cpu` @ 167h) to all `withName` blocks.
- Decide whether AlignReads on WGS needs its own ladder or if the WES
  ladder applies. WGS doesn't run AlignReads from FASTQ, but BWA-Spark
  steps may have similar walltime characteristics worth tiering.
- Verify the `meta.size > 100` time logic in WGS GATK4SPARK entries is
  still desired or should be replaced by the tier ladder.

## 2. Cross-config sharing of tier-ladder helpers

The `tierFor` / `queueFor` / `timeFor` closures and `shortMediumLongLadder`
are defined inline at the top of `conf/tempo-wes-iris.config`. When WGS-iris
gets the same logic, copy-pasting them will create a drift hazard. Options:

- Extract to `conf/lib/iris-tiers.config` (or similar) and `includeConfig`
  it from both `tempo-wes-iris.config` and `tempo-wgs-iris.config`.
- Define them once in `conf/iris.config` since they're cluster-specific
  (queue names are IRIS-specific). Risk: the helpers reference
  `task.previousTrace.realtime` which requires Nextflow 25.x — pinning
  is in `00.SETUP.sh` but config-level reliance is implicit.

## 3. Stale comments and version markers

- `conf/iris.config` line 7 header still says `// v2.3.7 2025-09-13`.
  Remove the version-stamping convention from per-cluster configs (it's
  meaningless after the first edit) or update it on every release.
- `conf/tempo-wgs-iris.config` line 8 says
  `// This one is hard coded with IRIS specific limits` — comment is
  stale; the file no longer hard-codes a single limit, it uses tiers.
  (Fixed in the WES config in `6f7fdbe`.)
- `conf/tempo-wgs-iris.config`: the SvABA comment block (around lines
  285-347) describes a 3-attempt 28/42/50-cpu ramp; the block is 42 cpus,
  48 then 320 GB, 2 attempts. Line 91 says "19 nodes x 56 cores";
  `cmobic_cpu` has 14 x 56-core and 5 x 96-core nodes.
- Both tempo configs' header (lines 1-4) says the options do not depend
  on the cluster.

## 4. Hardcoded user paths in run scripts

`bin/runTempoWESCohort.sh` and `bin/runTempoWGSBam.sh` hardcode
`/scratch/core001/bic/socci/...` for `NXF_SINGULARITY_CACHEDIR` and
`TMPDIR`. This works for `soccin` but not for any other user who tries to
run adagio. Options:

- Move to environment variables with sensible defaults (e.g. honor
  `$ADAGIO_SCRATCH` if set, fall back to `/scratch/core001/bic/$USER`).
- Source from a per-user config file under `$HOME/.config/adagio/` or
  similar.

## 5. `SLM/` directory pre-creation

The SBATCH header `-o SLM/adagio*.%j.out` assumes a `SLM/` subdirectory
exists in the user's run directory. If absent, `sbatch` fails to start the
job with no clear error. Fix at one of two layers:

- Add `mkdir -p SLM` at the very top of the run scripts. This does not
  help `sbatch`: SLURM opens the `#SBATCH -o` file before the script
  runs, and a foreground run ignores `#SBATCH` lines.
- Document the requirement prominently in `README.md` / `docs/install.md`.

## 6. Decide fate of `rel/*` branches after release

`rel/v3.1.0` still exists on local and origin after the merge into master
and tagging. Convention isn't established. Either:

- Delete `rel/*` branches automatically after their release is tagged
  (clean repo, but loses the rel-branch as historical staging area).
- Keep them around indefinitely as audit trail.
- Document the choice in `CLAUDE.md` so future runs of `/loop` or release
  prep agents handle it consistently.

## 7. End-to-end smoke test for IRIS WES tier logic

Nothing currently validates the new tier-ladder behavior automatically.
Manual checks needed on the first real run:

- Confirm attempt-1 jobs submit to `cpushort,cmobic_short` (not
  `cmobic_cpu`) — visible in `trace.txt` and `squeue`.
- Trigger a deliberate OOM kill and confirm the retry stays in short
  queue (because `previousTrace.realtime < 1h55m`).
- Trigger a walltime kill (e.g. set a process to a 1-minute task with a
  10-minute job) and confirm the retry escalates one tier.
- Verify `task.previousTrace.realtime` is being populated in Nextflow
  25.x — if not, the entire retry logic falls back to "treat as
  walltime" and we get the old behavior.

Worth scripting this as a `tests/iris-tier-smoke.nf` mini-pipeline once
the WGS parity work lands.

## 8. WGS-iris `params.minWallTime` provenance

`conf/tempo-wgs-iris.config` references `params.minWallTime` but
`conf/iris.config` only sets `maxWallTime`. The value comes through the
tempo `iris` profile's `includeConfig "conf/juno.config"` (which sets
`minWallTime = 3.h`). That's brittle — if tempo ever stops including
juno.config from the iris profile, WGS-iris breaks silently with NPE.

- Either set `params.minWallTime` explicitly in adagio's `iris.config`
  for safety, or refactor away the `meta.size > 100 ? max : min` pattern
  entirely (subsumed by item #1).

## 9. nfTraceReport.R failure modes

`runTempoWES/WGS` scripts unconditionally invoke
`Rscript $ADIR/scripts/nfTraceReport.R` after the nextflow block, piping
to `RUN_REPORT_*.md`. If R or any package dep is missing, the failure is
quiet (the pipe still creates an empty file). Worth:

- Adding `set -e` resilience: capture exit code, log a warning if the
  report fails, but don't fail the whole script.
- Document required R packages somewhere visible (currently scattered
  across `scripts/rsrc/nf-reports/*.R` `library()` calls).

## 10. Documentation drift

Done in v3.2.2: README and `CLAUDE.md` resume steps (each run has its
own scratch `WORKDIR`), `CLAUDE.md` entry points, reports and cleanup,
the Nextflow pin in `docs/install.md`.

- `scripts/resume00.sh` still uses JUNO paths (`/rtsess01/...`,
  `/scratch/socci`).

## 11. Code issues found in the v3.2.2 release review

- **WGS `doPost.sh` aborts with no WGS metrics.** `bin/doPost.sh` runs
  with `set -eu`, and `scripts/getWGSStats.R` calls `quit(status=1)`
  when it finds no `wgs.txt` metrics files. The WGS block then stops
  before `reportAll.R`, the `DESCRIPTION_ALL_REPORT.md` copy,
  `output.html` and `version.txt`. Either make getWGSStats.R warn and
  exit 0, or let doPost.sh continue past it.
- **`reportFacets01.R` prepends `Proj_` unconditionally** (output file
  names and the `.seg` files). The other reports skip the prefix when
  the project ID already starts with `Proj_` (`report01.R`), so a
  `Proj_`-prefixed ID gives `Proj_Proj_...`.
- **`bin/deliverGermline.sh`** calls `$BIC_DELIVERY/readme2yaml.R`
  (`$HOME/Code/BIC/Delivery/Version2j`), while `bin/deliver.sh` uses the
  copy in adagio, `$SDIR/readme2yaml.R`. Its usage text also says
  `deliver.sh`.
- **`bin/runTempoWGSBam.sh`** usage text and log name say
  `runTempoWGSBams.sh` (extra `s`).
- The WGS driver `nfTraceReport.R` run directory is item 9.
