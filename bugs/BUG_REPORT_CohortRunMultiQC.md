# BUG REPORT: CohortRunMultiQC fails on BAM-input WGS runs

Date: 2026-09-30
Project: Proj_18645_C_s2 (run 20260927_171517_3313, IRIS)
Process: `aggregateFromProcess:CohortRunMultiQC (default_cohort)`
Source: `tempo/modules/process/Aggregate/CohortRunMultiQC.nf`

Not fixed. The task failed three times with exit 1 and the error was
then ignored by the juno/iris error strategy, so the run completed but
the cohort MultiQC report is missing from `out/<proj>/cohort_level/`.

Work dirs (last attempt): `work/da/79777ce0e3585f72827f1847e37435`
(earlier attempts `1c/daa73632`, `cb/6214c76a`, all identical).

## Symptom

MultiQC itself completes. The helper `general_stats_parse.py`, which
runs immediately after the first `multiqc` call, expects
`multiqc_data/multiqc_general_stats.txt` and dies when it is absent:

```
|           multiqc | MultiQC complete
Traceback (most recent call last):
  File "/opt/conda/envs/multiqc/bin/general_stats_parse.py", line 36, in main
    genStats = pd.read_csv(args.originalgenstats, header=0, sep="\t", index_col=0)
FileNotFoundError: [Errno 2] No such file or directory: 'multiqc_data/multiqc_general_stats.txt'
```

## Root cause

Three conditions combine. All of them stem from running Tempo from BAMs
(`bin/runTempoWGSBam.sh`) instead of FASTQs.

### 1. Qualimap doubles the sample rows

Input BAMs are named `<sample>.recal.bam`, and `QcQualimap` runs
`qualimap bamqc -bam <sample>.recal.bam -outdir <sample>`. MultiQC's
qualimap module names the `genome_results.txt` sample from the
`bam file =` line (`<sample>.recal`) but names the coverage, GC and
insert-size stats from the directory (`<sample>`). MultiQC sees them as
two samples. In this run the general stats table had 42 rows for 21
samples, one bare and one `.recal` per sample.

In a FASTQ run the BAM is `<sample>.bam`, so both names coincide and
the table has one row per sample.

### 2. The table row limit is computed too low

`CohortRunMultiQC.nf` sets

```
samplesNum=`... contamination.txt ... | sort | uniq | wc -l`
fastpNum=`ls ./*fastp*json | wc -l`
mqcSampleNum=$((samplesNum + fastpNum ))
mqcSampleNum=$(( mqcSampleNum > 25 ? mqcSampleNum : 25 ))
multiqc . --cl_config "max_table_rows: $(( mqcSampleNum + 1 ))" ...
```

The fastp count is a proxy for "one extra row per sample". On a
BAM-input run there is no fastp step: the `fastPTumor`/`fastPNormal`
inputs are staged as empty placeholders (`input.112`, `input.113`),
`ls ./*fastp*json` fails, `fastpNum` is 0, and the limit becomes 26.

### 3. MultiQC 1.9 does not write the data file in beeswarm mode

Container: `cmopipeline-multiqc-0.1.3.img` (MultiQC v1.9). With 42
rows and `max_table_rows: 26` the log records

```
multiqc.plots.table  Plotting beeswarm instead of table, 42 samples
```

In `multiqc/plots/table.py` of this version, `write_data_file()` is
called only inside `make_table()` (line 429). The beeswarm branch in
`plot()` (line 43) returns before that, so
`multiqc_general_stats.txt` is never written. Later MultiQC releases
always write the file.

## Secondary issues in the same task (not fatal)

- `coverage_split.txt` is built with two chained `join` calls. The
  second join keys on the Normal column, but the first join's output
  is sorted by the Tumor column, so `join` warns `is not sorted` and
  drops rows. Only 7 of 12 tumor/normal pairs received a paired
  `Tumor_Coverage`/`Normal_Coverage` value. Pre-existing Tempo bug,
  independent of BAM input.
- `parse_alfred.py` prints `Something went wrong` / `No data for label
  OT_aware` on stdout. Noise; exit code unaffected.

## Fix options, least effort first

1. **Raise the row limit or disable beeswarm.** Set `max_table_rows` to
   `2 * samplesNum + 1` (or add `no_beeswarm: True` for the general
   stats table) in `CohortRunMultiQC.nf`. Guard the `ls ./*fastp*json`
   with `2>/dev/null` so it does not spam stderr. Cheapest, but leaves
   the duplicated `.recal` rows in the report.
2. **Normalize BAM names in the BAM-input path.** Symlink or rename
   `<sample>.recal.bam` to `<sample>.bam` before `QcQualimap` (or pass
   the bare name to `-bam`). Removes the duplicate rows and fixes the
   count without touching the MultiQC config. Preferred.
3. **Upgrade the MultiQC container** past 1.9 so the general stats file
   is always written. Larger change; the custom `general_stats_parse.py`
   and `parse_alfred.py` would need re-testing.
4. Fix the `join` ordering in the `coverage_split.txt` block (sort the
   intermediate on the join key, or use a single awk pass).

## Recovery for this project

The error was ignored, so a `-resume` rerun executes only this task
once one of the fixes above is applied.
