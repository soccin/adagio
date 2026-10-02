# WES parity with the WGS IRIS changes (2026-05-25 to 2026-09-27)

Written 2026-10-02. Scope: `conf/tempo-wes-iris.config` and
`bin/runTempoWESCohort.sh` against what was done to the WGS equivalents.

Basis for the numbers below: every COMPLETED task in the three exome
runs on IRIS that have execution traces (27,014 completed, 3,623 failed):

| Run | Date | Adagio | Workflows | Tasks |
|---|---|---|---|---|
| Proj_B-102-243 Pass_260507 | 2025-12-30 | v3-rc3-22 | germsnv,qc | 19,425 |
| Proj_17653_B | 2026-03-13 | v3-rc3-38 | snv,qc,facets | 237 |
| Proj_B-102-243 | 2026-05-27 | v3.1.0 | germsnv,qc | 10,975 |

The May run is the only one on the current short-queue ladder. It sent
10,974 of 10,975 tasks to `cpushort,cmobic_short` and escalated one
(a HaplotypeCaller shard, on a transient failure). The ladder works for
WES as designed.

## 1. What changed on the WGS side, and whether WES already has it

| Commit | Change | WES status |
|---|---|---|
| 448660c 2026-06-09 | Tiered queue/time ladder, `tierFor`/`queueFor`/`timeFor`, short-queue-first | **Already in WES.** WES was the origin (b45de4d, c522288, 913a5ea, 9e7526a, 2026-05-23/25). |
| bff362a 2026-06-09 | Right-size QcQualimap, DoFacets, Delly, SvABA | **Not in WES.** QcQualimap and DoFacets need porting, with WES-measured values. See section 2. |
| 3d2dc01, 6951659, 3328bb0, 1e207f2, 9a86294, 7d4d466 (Jul to Aug) | Delly/SvABA measured ladders, `rungFor`, `dellyLadder`, `svabaLadder`, `errorStrategy` override, cmobic_cpu pinning | **Do not port.** WGS-only measurements. See section 3. |
| 0a3e020 2026-09-27 | `qosFor`, process-level `clusterOptions`, `unset SBATCH_QOS`, driver on `cmobic_cpu` with `--qos=priority` | **Already in WES** (commit touched both configs and both scripts). |
| 2260b32 2026-08-08 | `bin/makeTempoBams.sh` | Already assay-aware (`--assay=exome` loads `tempo-wes-iris.config`). |
| JUNO configs | No commits to either JUNO config since 2025-09-26 | Nothing to port. |

Run scripts: `runTempoWGSBam.sh` and `runTempoWESCohort.sh` were changed
in lockstep for the whole period. Every remaining difference between them
is intentional (assay, defaults, `--anonymize`, mapping flag). There is
nothing to port to WES. See section 5 for one item going the other way.

## 2. Required: port the right-sizing (bff362a) with WES values

### 2a. QcQualimap (highest priority, a real failure source)

Current WES block:

```groovy
withName:QcQualimap {
  cpus = { 4 * task.attempt }
  memory = { 128.GB + 128.GB * task.attempt }
}
```

Tempo's module computes the Java heap as `0.75 * cpus * memory`, so
attempt 1 tells the JVM it may use 768 GB while SLURM enforces 256 GB.
The JVM grows into whatever heap it is allowed, so peak RSS tracks the
heap, not the work. Measured:

| Run | Attempt | cpus / mem | RSS p50 | RSS max | Outcome |
|---|---|---|---|---|---|
| Dec | 1 | 4 / 128 GB | 94 GB | 127 GB | 79 of 238 OOM-killed (exit 137) |
| Dec | 2 | 8 / 256 GB | 193 GB | 252 GB | 2 of 79 OOM-killed again |
| May | 1 | 4 / 256 GB | 98 GB | 204 GB | 131 of 131 completed |

Runtime is 0.15 h median, 0.44 h max. The job is small; the memory
figures are an artifact of the heap formula. WGS fixed exactly this in
d67e8fc and bff362a by fixing memory and passing an explicit `--mem`
that matches what Tempo actually hands the JVM. A WGS run on 2026-08-30
confirms the override wins over Nextflow's own `--mem`: an 8 cpu / 20 GB
QcQualimap completed with 77.8 GB peak RSS.

Port the WGS block verbatim:

```groovy
withName:QcQualimap {
  cpus = { task.attempt<=2 ? 4 : 8 }
  memory = { 20.GB } // N.B. Tempo multiplies mem by cpus for this process

  // Request what Tempo actually hands the JVM (0.75 * cpus * mem), +10%
  clusterOptions = {
    def requestedMem = task.cpus * task.memory.toGiga() * 1.1
    "--mem=${requestedMem.intValue()}G ${qosFor(task)}".trim()
  }
}
```

That gives the JVM a 60 GB heap and SLURM an 88 GB request. Exome BAMs
are 10 to 20 times smaller than the WGS BAMs this was sized for, so it
cannot OOM. It packs 11 per node by memory against 13 by cores on
`cpushort`, so the cost over a tighter figure is small. If you want it
tighter, `memory = { 8.GB }` gives a 24 GB heap and a 35 GB request; the
true need cannot be read from the traces because RSS follows the heap.

Also update the process-level comment above `clusterOptions` in the WES
config to point at QcQualimap, as the WGS one does.

### 2b. DoFacets

Current WES block is the blanket `4 + 12 * attempt` cpus / `246.GB *
attempt`. WGS went to 2/4 cpus and 64/128 GB. WES measurement over 251
tasks: 101% CPU, RSS p50 3.6 GB, p95 6.3 GB, max 13 GB, runtime max
0.43 h. Exome Facets runs at `cval = 100` on far fewer SNPs than WGS, so
do not port the WGS 64 GB. Suggested:

```groovy
withName: DoFacets {
  cpus = { 2 }
  memory = { task.attempt <= 2 ? 16.GB : 32.GB }
  // queue/time: inherit the process-level short-queue ladder
}
```

16 GB is 1.2x the observed max and 2.5x the p95.

### 2c. What bff362a did to Delly and SvABA

Superseded on the WGS side by the measured ladders. Not applicable to
WES. See section 3.

## 3. Do not port: the WGS SV-caller work

Everything from 3d2dc01 through 7d4d466 (`rungFor`, `dellyLadder`,
`svabaLadder`, cmobic_cpu pinning, 320 GB second rung, two-attempt
`errorStrategy`) is sized from 811 WGS Delly and 162 WGS SvABA tasks.
There are zero WES SV tasks on IRIS to size from, and `sv` is not in
the WES default workflow set.

The exome `sv` workflow does run Delly, Manta and SvABA (not BRASS,
`sv_wf.nf` gates that on genome). If someone passes `--add-workflows=sv`
on a WES run, the current WES blocks are wrong in a different way from
the old WGS ones:

- `SomaticDellyCall`: `160.GB * attempt`, 2 h first attempt. 160 GB per
  task caps `cpushort` at 6 tasks per node for a job that on WGS peaks
  at 18 GB (p99).
- `.*RunSvABA`: `32 + 5 * attempt` cpus and `96.GB * attempt`. 37 cpus is
  one task per node.

Suggested placeholders until a WES `sv` run produces traces. Both stay
on the inherited short-queue ladder, since an exome BAM should clear 2 h
and there is no evidence either way:

```groovy
withName: SomaticDellyCall {
  cpus = { 2 }
  memory = { 16.GB * task.attempt }
}
withName: '.*RunSvABA' {
  cpus = { 8 }
  memory = { 16.GB * task.attempt }
}
```

Mark them in a comment as unmeasured, and escalate only on evidence
(exit 137 for memory, `caught USR2/TERM signal` at the cap for time) as
`docs/IRIS_SLURM.md` section 6 prescribes.

## 4. Beyond parity: WES-measured right-sizing the WGS side never did

These blocks are identical in both configs. WGS left them alone because
WGS tasks do fill them. WES tasks do not. None of this is required for
parity; it is listed because the measurements are unambiguous and the
fix is free. All of these keep the inherited short-queue ladder.

| Process | Tasks | Current request | CPU p50 | RSS max | Runtime max | Suggested |
|---|---|---|---|---|---|---|
| `multiqc_process` label (SampleRunMultiQC, SomaticRunMultiQC) | 623 | 16 cpu / 34 GB | 142% | 0.4 GB | 0.01 h | 2 cpu / 4 GB x attempt |
| SomaticAnnotateMaf | 2 | 16 cpu / 34 GB | 63% | 3.7 GB | 0.09 h | 2 cpu / 8 GB x attempt |
| SomaticFacetsAnnotation | 2 | 16 cpu / 34 GB | 170% | 0.2 GB | 0.01 h | 2 cpu / 4 GB x attempt |
| MetaDataParser | 251 | 16 cpu / 246 GB | 238% | 0.1 GB | <0.01 h | 2 cpu / 2 GB x attempt |
| GermlineRunStrelka2 | 249 | 16 cpu / 246 GB | 1168% | 1.2 GB | 0.09 h | 8 cpu / 8 GB x attempt |
| GermlineCombineChannel | 249 | 16 cpu / 246 GB | 100% | 3.6 GB | 0.08 h | 2 cpu / 8 GB x attempt |
| SomaticRunStrelka2 | 2 | 16 cpu / 246 GB | 1307% | 1.6 GB | 0.14 h | 8 cpu / 8 GB x attempt |
| SomaticRunManta | 2 | 16 cpu / 246 GB | 1176% | 1.6 GB | 0.06 h | 8 cpu / 8 GB x attempt |
| SomaticCombineChannel | 2 | 16 cpu / 246 GB | 224% | 4.9 GB | 0.04 h | 2 cpu / 8 GB x attempt |
| CohortRunMultiQC | 3 | 16 cpu / 246 GB | 117% | 39 GB | 0.38 h | 4 cpu / 64 GB x attempt |

Strelka2 and Manta do use their 16 cores (1170 to 1300%), so halving
cpus roughly doubles a 5 to 8 minute job. Keep 16 if you prefer; the
memory is the waste. A 246 GB request packs 3 per node and the QoS
memory cap of 58 TB allows 236 of them cluster-wide, so a large germline
cohort (the May run had 249 pairs) does feel it.

The somatic rows rest on two tasks each (Proj_17653_B had one pair).
Treat those suggestions as starting points.

Blocks that are already correctly sized for WES and should stay:
GATK4SPARK_MARKDUPLICATES (16 cpu / 80 GB, RSS max 68 GB),
GATK4SPARK_BASERECALIBRATOR (36 GB, RSS max 20 GB), GATK4SPARK_APPLYBQSR
(72 GB, RSS max 26 GB), RunMutect2 (RSS 3 GB), GermlineRunHaplotypecaller
(3 failures in 7,470 on the May settings; the Dec run's 3,505 failures
were on the pre-b827cd5 memory).

### AlignReads: leave it, but know what it does

AlignReads is the only WES process near the 2 h door: at 8 cpus the May
run's p90 was 0.91 h and the max 1.87 h (a large normal, 41 GB RSS).
The `shortMediumLongLadder` handles the tail (3 h on `cmobic_short`,
then `cmobic_cpu`). Two things worth knowing:

- The `memory = { 15.GB }` in the config is not the request. Tempo's
  module replaces `task.memory` with `inputSize * cpus * 1.1` (because
  `mem_per_core = false` on IRIS), and sets `samtools sort -m` to the
  full input size per thread. Observed requests were 7 to 98 GB. The 15
  GB only acts as a ceiling for inputs above roughly 110 GB.
- Because memory scales with cpus, raising AlignReads cpus raises its
  memory request in proportion. That is why the WES CPU formula was cut
  to `4 + 4 * attempt` in May (b946826, 6bcad83). Do not port the WGS
  `16 + 8 * attempt`.

## 5. Scripts

Nothing to port into `runTempoWESCohort.sh`. Two small items in the
other direction:

- `runTempoWGSBam.sh` still does `cd $WORKDIR` and then runs
  `nfTraceReport.R` there. The report searches `out/` relative to the
  current directory, which lives in the project directory, not in
  `$WORKDIR`. Commit 894e4bb fixed this with `pushd`/`popd` in the WES
  script only. Apply the same to the WGS script and to the usage string
  typo (`runTempoWGSBams.sh`).
- The WES script's JUNO branch lacks `export NXF_OPTS='-Xms1g -Xmx4g'`;
  the WGS script has it. Cosmetic, but add it for consistency.

## 6. Unmerged WGS work on `devs/iris` (not in master)

`devs/iris` is 9 commits ahead of master (last merge from master
2026-09-23). Three are WGS changes that belong in this review:

| Commit | Change | WES relevance |
|---|---|---|
| 44e88f7 2026-09-05 | `skipQualimap = true` in the WGS config; QcQualimap pinned to `cmobic_cpu`, 30 h then 167 h. Needs the Tempo submodule on `devs/iris`. | **Abandoned.** Superseded by master: Proj_18645_C (2026-09-27, master at 087d962) completed all 12 WGS QcQualimap tasks on the master block, 10 of them in 2.4 to 3.1 h on attempt 2 and the two slow ones in 21 and 24 h. Not relevant to WES either way; see section 2a. |
| 8b7056b 2026-09-07 | `.*AnnotateSVBedpe` memory 32 GB x attempt on IRIS (was falling through to 8 GB, OOM, and a silent bad report). | Only with `--add-workflows=sv`. Port alongside the section 3 placeholders; no WES measurement, but the failure mode is silent, so err high. |
| 3a7a77e 2026-09-07 | `--mail-user` / `--mail-type=END,FAIL` in the WGS driver header. | **Port to `runTempoWESCohort.sh`.** Note the branch's header still says `cmobic_cpu,bic_devs`; master's 0a3e020 header (`cmobic_cpu` plus `--qos=priority`) must win when the two merge. |

The remaining commits are docs, CHANGELOG, VERSION and the `.gitmodules`
branch pin. Decide whether `devs/iris` merges to master before or after
the WES work; the WES branch should start from whichever state will hold
the submodule it is tested against.

## 7. Suggested order

1. New branch (a name like `feat/wes-iris-01`; nothing by that name
   exists): section 2a (QcQualimap) and 2b (DoFacets), plus the comment
   fix and the mail directives from section 6. This is the parity work.
   Proj_16083_I is an IDT_Exome_v2 cohort and is the natural first test.
2. Same branch or a second one: section 4, at least the `multiqc_process`
   label and the 246 GB rows that WES default workflows actually hit
   (MetaDataParser, CohortRunMultiQC; the Strelka2/Manta/CombineChannel
   rows only matter with `germsnv` or `--add-workflows=sv`).
3. Section 3 placeholders and the AnnotateSVBedpe rule, clearly commented as unmeasured.
4. Section 5 reverse fixes to the WGS script.

After the first run on the new settings, rerun the trace summary
(`/tmp/wes_trace_stats.R` was a throwaway; the project's
`scripts/nfTraceReport.R` plus `rsrc/nf-reports/trace_parser.R` can be
extended to emit the same per-process table) and tighten from
measurement.
