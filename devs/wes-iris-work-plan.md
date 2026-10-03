# WES IRIS config plan: WGS rules, WES sizes

Written 2026-10-02, on `devs/iris` at `fdb922a`.

## Goal

Apply the rules the WGS IRIS work followed to `conf/tempo-wes-iris.config`:
- Size each process from measured runs.
- Stay under the 2-hour door.
- Request memory explicitly where tempo multiplies it by cpus.
- Escalate only on evidence.

Use WES-measured numbers, not WGS ones. WES does not run SV, so none of
the WGS SV work (Delly/SvABA ladders, AnnotateSVBedpe) applies.

## Data

Nine exome runs, 41,842 tasks, 38,150 of them COMPLETED. Parsing scripts
are in `/tmp/wes_traces/`. Two of the eleven paths were dropped:
- `Proj_17653/PDX/BAMRegen` has an empty trace.
- `Set_2511/SAFE` is a byte-identical copy of `Set_2511`.

| Run | Started | Cluster | Workflows seen | Tasks |
|---|---|---|---|---|
| P17664_Germ | 2025-10-07 | IRIS (`test01`) | snv, germsnv, qc, facets | 298 |
| P17653_Tum | 2025-10-10 | JUNO | snv, qc, facets | 231 |
| P17653_PDX | 2025-10-11 | JUNO | snv, qc, facets | 572 |
| B243_s2511 | 2025-12-03 | JUNO | germsnv, qc, facets | 7,981 |
| B243_s2512 | 2025-12-30 | IRIS (old flat config) | germsnv, qc, facets | 19,425 |
| P17653_B | 2026-03-13 | IRIS (old flat config) | snv, qc, facets | 237 |
| B243_May | 2026-05-27 | IRIS (current ladder) | germsnv, qc, facets | 10,975 |
| P17653_C_Tum | 2026-08-17 | IRIS (current ladder) | snv, qc, facets | 1,702 |
| P17653_C_PDX | 2026-09-12 | IRIS (current ladder) | snv, qc, facets | 421 |

How the JUNO rows are used:
- Their peak RSS is valid evidence of what a task needs.
- Their runtime is from different hardware, but it lands in the same
  range as IRIS.
- Their memory request is per core (`mem_per_core = true`).

**`SomaticRunManta` is not SV.** It runs in `snv`: tempo's `manta_wf`
supplies candidate indels to Strelka2. It appears in every `snv` run
above and must stay.

## 1. QcQualimap: the only measured failure

| Setting | Heap tempo gives the JVM | SLURM limit | Result |
|---|---|---|---|
| IRIS Oct/Dec, 4 cpu x 128 GB | 0.75 x 512 = 384 GB | 128 GB | 80 of 241 OOM (exit 137) |
| IRIS current, 4 cpu x 256 GB | 768 GB | 256 GB | completed; RSS up to 230 GB because RSS grows to fill the heap |
| **JUNO, 2 cpu x 6 GB/core** | **12 - 1 = 11 GB** | 12 GB | **126 of 126 completed, RSS max 7.9 GB, runtime max 0.57 h** |

The JUNO setting is tempo's own exome default
(`tempo/conf/resources_juno.config:221`: 2 cpus, `6.GB * attempt`). It
worked because JUNO multiplied memory by cpus. On IRIS, Nextflow would
request only 6 GB while tempo hands the JVM 11 GB.

The fix is the WGS mechanism (explicit `--mem`) with the WES size.
Qualimap is Java, so it gets 3 cpus (decision of 2026-10-02). Memory per
cpu drops to 4 GB to keep the heap JUNO proved:

```groovy
withName:QcQualimap {
  cpus = { 3 }
  memory = { 4.GB * task.attempt } // N.B. Tempo multiples mem by cpu's for this process

  // Calculate what TEMPO actually uses
  clusterOptions = {
    def requestedMem = task.cpus * task.memory.toGiga() * 1.1  // Add 10% buffer
    "--mem=${requestedMem.intValue()}G ${qosFor(task)}".trim()
  }
}
```

Result:
- Attempt 1 gets an 11 GB heap (3 x 4 = 12, minus 1) and a 13 GB
  request.
- Attempt 2 gets an 18 GB heap (0.75 x 24) and a 26 GB request.
- 17 tasks fit per node by cpus, against 3 now.
- `-nt` becomes 3. On JUNO it was 4 (`cpus * 2` in the older tempo).

## 2. Oversized blocks

All of these finish in under 0.6 h and stay on the inherited 2 h short
queue. The suggested memory is about 1.5 to 2x the measured max, and it
doubles on retry.

CPU rule (decision of 2026-10-02): at least 2 cpus, and 3 for anything
that runs Java. None of the processes below run Java; QcQualimap is the
only Java process being resized. Multithreaded tools keep their measured
count (Strelka2 and Manta: 8).

| Process | Current | Tasks | %cpu p50 | RSS p99 / max | Runtime max | Proposed cpus / memory |
|---|---|---|---|---|---|---|
| DoFacets | 16 / 246 GB | 336 | 100% | 11.9 / 13 GB | 0.52 h | 2 / `16.GB * attempt` |
| MetaDataParser | 16 / 246 GB | 336 | 236% (for under 5 s) | 0.09 / 0.10 GB | under 0.01 h | 2 / `2.GB * attempt` |
| `multiqc_process` label (Sample-, SomaticRunMultiQC) | 16 / 34 GB | 866 | 140% | 0.37 / 0.38 GB | 0.01 h | 2 / `2.GB * attempt` |
| CohortRunMultiQC | 16 / 246 GB | 9 | 116% | 39 GB (249-pair cohort) | 0.38 h | 2 / `64.GB * attempt` |
| SomaticRunStrelka2 | 16 / 246 GB | 29 | 1300% at 16, 730% at 8 | 1.9 GB | 0.28 h at 16, 0.33 h at 8 | 8 / `4.GB * attempt` |
| SomaticRunManta | 16 / 246 GB | 29 | 1190% | 1.8 GB | 0.13 h | 8 / `4.GB * attempt` |
| GermlineRunStrelka2 | 16 / 246 GB | 308 | 1170% at 16, 685% at 8 | 1.2 GB | 0.11 h at 16, 0.18 h at 8 | 8 / `4.GB * attempt` |
| SomaticCombineChannel | 16 / 246 GB | 29 | 130% | 4.9 GB | 0.06 h | 2 / `8.GB * attempt` |
| GermlineCombineChannel | 16 / 246 GB | 309 | 100% | 3.6 GB | 0.11 h | 2 / `8.GB * attempt` |
| SomaticAnnotateMaf | 16 / 34 GB | 29 | 87% | 4.5 / 4.8 GB | 0.09 h | 2 / `8.GB * attempt` |
| SomaticFacetsAnnotation | 16 / 34 GB | 29 | 190% | 0.17 GB | under 0.01 h | 2 / `2.GB * attempt` |

`withName: CohortRunMultiQC` overrides the `multiqc_process` label, so the
two can be sized separately.

**Strelka2/Manta:** at 8 cpus, the JUNO runs took 2 to 3x as long by
median runtime. The max was still 20 minutes, and 8 cpus fit twice as
many tasks per node.

**Germline cohorts:** in the 249-pair cohort, MetaDataParser, DoFacets
and both CombineChannel processes each requested 246 GB per task. The
58 TB QoS memory cap then limits that cohort to 236 tasks at once.

## 3. Watch items (no change proposed)

- **GermlineAnnotateMaf:** has no adagio block and gets tempo's 1 cpu /
  6 GB. RSS max is 5.4 GB (90% of the request), with 0 failures in 309
  tasks. If one OOMs, add `8.GB * attempt`.
- **SplitLanesR1/R2:** 2 cpus, 1 GB, runtime max 1.86 h. 3 of 652 tasks
  ran past 1.5 h and none passed 2 h.
  - If one hits the 2 h limit, the process-level rule sends the retry to
    `cmobic_cpu` at 48 h.
  - Decision of 2026-10-02: leave them as they are. Move them to
    `shortMediumLongLadder` only after a real walltime kill.
- **GermlineRunHaplotypecaller:** b827cd5 (2026-05-27) raised it from
  2 cpu / `5.GB` to `2 * attempt` cpu / `8.GB * attempt`.
  - On the old setting, the May run completed 3,897 tasks with RSS max
    3.1 GB.
  - Its 3 failures were exit 250 within 5 s, which is transient, and all
    3 passed on retry.
  - The new setting is larger than needed but harmless: packing is
    limited by cpus, not memory.
  - No WES run has used it yet.
  - Decision of 2026-10-02: keep b827cd5.
- **AlignReads:** leave it. On the current settings (8 cpus) the max was
  1.87 h, and the ladder covers the tail. One P17664 sample at 16 cpus
  ran 2.14 h. Tempo sets its memory from input size, which is why that
  run requested 437 GB.

## 4. Already the right size: leave alone

| Process | Current | Measured RSS max | Note |
|---|---|---|---|
| GATK4SPARK_MARKDUPLICATES | 16 / 80 GB | 68 GB | JVM; JUNO failed at 80 GB total with exit 50/52 |
| GATK4SPARK_BASERECALIBRATOR | 4 / 36 GB | 20 GB | |
| GATK4SPARK_APPLYBQSR | 8 / 72 GB | 44 GB | |
| GATK4SPARK_SETNMMDANDUQTAGS | 4 / 12 GB | 2.9 GB | |
| MERGE_* / INDEX_* | 8 / 24 GB | 0.04 GB | memory is waste, but packing is limited by cpus; optional cut to `4.GB` |
| RunMutect2 | 3 / 15 GB | 3.4 GB | `-Xmx8g` hard-coded in tempo |
| QC: Alfred, Pileup, HsMetrics, Conpair, FacetsPreviewQC | tempo defaults | at most 2.5 GB | |

## 5. SV-only blocks in the WES config

These processes cannot run in a WES workflow:
- `.*RunSvABA`
- `SomaticDellyCall`
- `GermlineDellyCall`
- `runBRASS.+` and `runBRASS`
- `GermlineRunManta`
- `SomaticRunSVclone` (clonality, needs SV)
- `HRDetect` (needs SV)

Decision of 2026-10-02: leave them in place. Do not resize them and do
not add WGS SV rules (AnnotateSVBedpe, Delly/SvABA ladders).
`SomaticRunManta` is not in this list; it is part of `snv` and is resized
in section 2.

No WES trace data exists for RunMsiSensor, RunMutationSignatures,
RunLOHHLA, RunPolysolver or RunNeoantigen. These are valid WES workflows,
so leave them as they are.

## 6. Scripts

`runTempoWESCohort.sh` needs nothing.
- It already has `unset SBATCH_QOS`, the `cmobic_cpu` driver, mail on job
  end or failure, and `pushd`/`popd` around the trace report.
- `runTempoWGSBam.sh` is the one that needs the `pushd`/`popd` fix (TODO
  item 9).

## 7. Order

1. Branch from `devs/iris`.
2. `fix(conf)`: QcQualimap (section 1).
3. `fix(conf)`: right-size the section 2 blocks.
4. `docs(conf)`: fix the stale header ("WGS specific options", "hard
   coded with IRIS specific limits").
5. Test on Proj_16083_I. Check:
   - QcQualimap exit codes and runtime at `-nt 3`
   - DoFacets RSS
   - that every attempt-1 task goes to `cpushort,cmobic_short`
6. Replace `devs/wes-iris-parity-report.md`. Its QcQualimap advice
   (copy the WGS 20 GB block) and its SV sections are superseded by this
   file.
