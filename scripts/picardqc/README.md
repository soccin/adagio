# Picard QC after a WES run (picardqc)

`doPicardQC.sh` runs two Picard tools (GATK 4.1.0.0, the version Tempo
uses) on the final BAM of every sample of a finished WES run:

| Tool | `-t` | Why | Output |
|---|---|---|---|
| CollectHsMetrics | `hs` | Tempo runs it with Picard's default `COVERAGE_CAP` of 200; this reruns it with 1000 | `<SAMPLE>.hs_metrics.txt` |
| CollectAlignmentSummaryMetrics | `asm` | Tempo does not run it; chimeras, mismatch rate, aligned fraction | `<SAMPLE>.asm.txt` |

Both use the same BAMs, reference and container as Tempo. Until
adagio v3.2.3 this folder was `scripts/hsmetrics/` and ran only
CollectHsMetrics (`doHsMetrics.sh`).

## CollectHsMetrics: what the cap changes

From the Picard 2.18.25 source (the version in GATK 4.1.0.0,
`TargetMetricsCollector.java`):

| Output | Effect of the cap |
|---|---|
| `MEDIAN_TARGET_COVERAGE` | taken from the capped histogram, so it stops at the cap |
| coverage histogram | bases deeper than the cap are counted in the last bin |
| `FOLD_80_BASE_PENALTY` | mean / 20th percentile of the capped histogram; wrong once the 20th percentile reaches the cap |
| `HS_PENALTY_*X` | computed from the capped histogram; wrong for the same samples as fold-80 |
| `HET_SNP_SENSITIVITY`, `HET_SNP_Q`, `unfiltered_baseq_count` | computed from the capped unfiltered depth histogram |

The cap does not affect `MEAN_TARGET_COVERAGE`, `MAX_TARGET_COVERAGE`,
`PCT_TARGET_BASES_*X`, `ZERO_CVG_TARGETS_PCT`, the read and base counts,
or the `PCT_EXC_*` fractions; Picard computes these from the uncapped
depths.

In the WES IDT v2 background run (200 pairs), 102 of 200 tumors have a
Tempo median of exactly 200.

Test on that run (2026-11-23):

- Cap 200 on `P-0003247-T01-WES` reproduced Tempo's file exactly (every
  metric and the whole histogram), so the inputs and options match.
- Cap 1000: `P-0003247-T01-WES` median 200 -> 256, het sensitivity
  0.976951 -> 0.976943, nothing else changed. `P-0031241-T01-WES` (the
  deepest tumor) median 200 -> 337, fold-80 1.81 -> 1.59, and every
  `HS_PENALTY_*X` lower by about 13%. Normal `P-0021872-N01-WES`
  (median 162): no metric changed; only the histogram extends past 200.

Full run on all 400 samples (array job 13302191, 2026-11-23): every task
completed, and no sample reached the 1000 cap. Tumors at exactly 200
dropped from 102 to 1 (a true median of 200); tumor medians are now 99
to 337 (median 203). Normal metrics are unchanged.

### Why the default cap is 1000

Picard's het SNP sensitivity only uses depths up to 1000
(`MAX_CONSIDERED_DEPTH_HET_SENS` in `TheoreticalSensitivity.java`). With
a cap of 1000, bases deeper than 1000 are counted at 1000 and still
count toward the sensitivity. With a cap above 1000, they are dropped
from it, and `HET_SNP_SENSITIVITY` comes out slightly low. A cap of 1000
keeps the median, histogram and fold-80 correct for any sample with a
median under 1000, and keeps the sensitivity calculation complete.

If a sample's median reaches the cap, its job log has a `WARNING` line;
rerun that sample with a higher `-c`.

## CollectAlignmentSummaryMetrics

Run with the reference FASTA (without it Picard skips the mismatch
metrics) and Picard's defaults otherwise: a pair counts as chimeric if
the mates are on different chromosomes, more than 100 kb apart
(`MAX_INSERT_SIZE`), or not in FR orientation. The file has one row
per category: `FIRST_OF_PAIR`, `SECOND_OF_PAIR` and `PAIR`. The QC
database takes the `PAIR` row as its `ASM_` columns.

The tool counts every primary read, duplicates included.
`PCT_ADAPTER` is close to 0, because fastp trims adapters before
alignment.

## Run

`bin/runTempoWESCohort.sh` runs it at the end of a WES run, with
`-p <PROJECT_ID>`, when nextflow exits 0. It submits the array and
returns, so the run job ends before the Picard jobs do. Wait for
them before `deliver.sh`, so the files are delivered. A failure of
`doPicardQC.sh` is printed in the run log but does not change the run
script's exit code. It does not depend on `doPost.sh`.

To run it by hand (a run from before this change, a nextflow failure
that was resumed by hand, or failed tasks), from the project folder
(the one that holds `out/`):

```
<adagio>/scripts/picardqc/doPicardQC.sh -n    # dry run: tasks and inputs
<adagio>/scripts/picardqc/doPicardQC.sh
```

The driver reads the run log `out/<PROJECT_ID>/runlog/cmd.sh.log` for
the mapping file, `TARGETS_BASE` and `REFERENCE_BASE`, writes a sample
sheet with one row per sample and tool, and submits one SLURM array
task per row (`runPicardQC.sh`), then returns. An output that already
exists is skipped, so a run that has the HsMetrics files gets only the
`asm` tasks. It stops before submitting if any sample is missing a BAM
or intervals, and only runs on exome runs. `doPicardQC.sh -h` lists the
options (`-p` project, needed when `out/` holds more than one run; `-t`
tools; `-c` cap; `-o` output folder; `-s` samples; `-m` tasks at once;
`-f` redo).

Each task: 1 CPU, 6 GB, 2 h, `cpushort,cmobic_short`. Temp files go to
`/localscratch/$USER/picardqc/$SLURM_JOB_ID`, mounted over `/tmp` in the
container.

- `hs`: in the background run, Tempo's tasks took 7-39 min (median 16)
  with a 1.5 GB peak at cap 200. At cap 1000, the 400 tasks took 6-40
  min (normals about 10 min, tumors about 20), and the whole array, 100
  at a time, took about 1.5 h. The four test jobs had a `sacct` MaxRSS
  of 6.0 GB, the full request, with no OOM kill: the figure is the
  job's memory limit, not a measured peak (`docs/IRIS_SLURM.md`
  section 6).
- `asm`: test on the background run (array job 13380038, 2026-11-23):
  normal `P-0021872-N01-WES` (171M reads) 10 min, the deepest tumor
  `P-0031241-T01-WES` (415M reads) 31 min, both `COMPLETED 0:0`. Java
  used about 2 GB of its 4 GB heap; `sacct` MaxRSS was 6.0 GB, the job
  limit, as for `hs`. Full run on the other 398 samples (array job
  13386723, 100 at a time): every task `COMPLETED 0:0`, 5-31 min.

Check a submission:

```
sacct -j <jobid> --format=JobID,State,ExitCode,Elapsed,MaxRSS
grep "at COVERAGE_CAP" SLM/picardQC.<jobid>_*.out
```

Rerunning the driver submits only the outputs that are missing.

Logs may have the line `WARNING: BAM index file ... is older than BAM`.
It comes from htsjdk and is harmless: the tools read the whole BAM and
do not use the index. The cap warning reads `WARNING: <SAMPLE> median
target coverage is at COVERAGE_CAP`.

## Output

| Path | Contents |
|---|---|
| `out/<PROJECT_ID>/post/qc/<SAMPLE>.hs_metrics.txt` | HsMetrics, same format and name as Tempo's file |
| `out/<PROJECT_ID>/post/qc/<SAMPLE>.asm.txt` | AlignmentSummaryMetrics |
| `out/<PROJECT_ID>/post/qc/runlog/samples_<timestamp>.tsv` | the sample sheet of each submission |
| `SLM/picardQC.<jobid>_<task>.out` | job logs |

The HsMetrics file names match Tempo's
(`out/<PROJECT_ID>/bams/<SAMPLE>/collecthsmetrics/`), so code that
searches `out/` for HsMetrics files must say which folder it wants.
`qcReport01.R` reads only the `bams/` copies (Tempo's);
`scripts/qcdb/buildQCDb.R` reads `post/qc` by default. `deliver.sh`
copies `out/`, so the files are delivered.

## Files

- `doPicardQC.sh`: finds the inputs and submits the array
- `runPicardQC.sh`: one sample and tool (SLURM array task)
