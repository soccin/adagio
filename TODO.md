# Adagio TODO

Items to address after v3.1.0. Ordered by impact, not effort.

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
- `conf/tempo-wes-iris.config` line 8 says
  `// This one is hard coded with IRIS specific limits` — comment is
  stale; the file no longer hard-codes a single limit, it uses tiers.

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

- Add `mkdir -p SLM` at the very top of the run scripts (before they
  fail-fast), so even foreground `bash bin/runTempo...` invocations don't
  hit this.
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

- `README.md` "Resume" section still references JUNO-specific paths
  (`/rtsess01/...`, `/scratch/socci`). Add an IRIS variant or generalize.
- `docs/install.md` does not mention the Nextflow version pin
  (`NXF_VER=25.10.4` in `00.SETUP.sh`). Mention that bumping past 25.x
  breaks the `task.previousTrace.realtime` retry logic.
- `CLAUDE.md` lists v3.0.0 features as current; the post-processing
  reports table is still accurate but the assertion "Current version:
  v3.1.0" alongside the v3.0.0-era doc body could confuse future
  readers/agents.
