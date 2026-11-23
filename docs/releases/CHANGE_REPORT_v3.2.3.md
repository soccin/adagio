# Adagio v3.2.3 Change Report

Changes from v3.2.2 (2026-10-03) to v3.2.3 (2026-11-23).

---

## Overview

v3.2.3 is a patch release on the **Cordelia** line: 45 non-merge commits
since v3.2.2, not counting the release documentation. The tempo submodule
is unchanged at `a7ecd35a` (branch `devs-iris`). IRIS is the only
supported cluster, and the JUNO code is now removed.

Headline items:

1. **Uncapped HsMetrics for WES.** Tempo's Picard CollectHsMetrics caps
   coverage at 200x, so half of WES tumors reported a median target
   coverage of exactly 200. Every WES run now also gets a rerun at a 1000x
   cap in `out/<ID>/post/qc/`.
2. **QC background database.** A builder that collects every QC output of
   a finished run into one `.rds`, an index that finds it, and the first
   database: 200 WES IDT v2 tumor/normal pairs.
3. **No silent loss of a sample or pair.** The mapping converters stop on
   bad input, the run scripts check that every pair has its output, and
   the WES reports list any pair that is missing.
4. **Delivery.** Dry run (`-n`), a FACETS-free delivery (`-r`), group
   `grp_hpc_core001` with group-writable folders, and a rewritten email.
5. **JUNO code removed.**

---

## 1. Uncapped HsMetrics (`scripts/hsmetrics/`)

New in this release (`5fdad87`, `37b010c`).

Tempo runs Picard CollectHsMetrics (GATK 4.1.0.0) with Picard's default
`COVERAGE_CAP` of 200. From the Picard 2.18.25 source, the cap limits
`MEDIAN_TARGET_COVERAGE`, the coverage histogram, `FOLD_80_BASE_PENALTY`,
`HS_PENALTY_*X` and the het SNP sensitivity inputs. Mean coverage,
`PCT_TARGET_BASES_*X`, read counts and the `PCT_EXC_*` fractions are not
affected.

- `doHsMetrics.sh`: run from the project folder. Reads the mapping,
  `TARGETS_BASE` and `REFERENCE_BASE` from `out/<ID>/runlog/cmd.sh.log`,
  writes a sample sheet and submits one SLURM array task per sample
  (1 CPU, 6 GB, 2 h, `cpushort,cmobic_short`, 100 at a time). Exome runs
  only. Skips samples that already have output, so a rerun submits only
  what is missing. Options: `-p` project (needed when `out/` holds more
  than one run), `-c` cap (default 1000), `-s` samples, `-f` redo, `-n`
  dry run.
- `runHsMetrics.sh`: one sample, the same image and options as Tempo
  except the cap. Temp files go to `/localscratch/$USER/hsmetrics/<job>`,
  mounted over `/tmp` in the container. Logs a `WARNING` if the median
  reaches the cap.
- Default cap 1000: Picard's het SNP sensitivity only uses depths up to
  1000 (`MAX_CONSIDERED_DEPTH_HET_SENS`), so a higher cap would drop deep
  bases from it.
- `runTempoWESCohort.sh` runs `doHsMetrics.sh -p <ID>` at the end when
  nextflow exits 0. It submits the array and returns. The script now takes
  nextflow's exit status from `PIPESTATUS`; before, the pipe into `tee`
  hid a nextflow failure. A `doHsMetrics.sh` failure is printed but does
  not change the exit code, which is still the pair check's.
- Output `out/<ID>/post/qc/<SAMPLE>.hs_metrics.txt` has the same name and
  format as Tempo's file under `bams/`, so code that searches `out/` must
  name the folder. `qcReport01.R` now reads only `bams/`.

Tests on the 200-pair WES IDT v2 background run (2026-11-23):

- Cap 200 on one tumor reproduced Tempo's file exactly, so the inputs and
  options match.
- All 400 samples at cap 1000: every task completed, in 6-40 min (normals
  about 10, tumors about 20); the whole array took about 1.5 h. No sample
  reached the cap.
- Tumors at a median of exactly 200: 102 before, 1 after (a true median
  of 200). Tumor medians now run 99-337, median 203. The deepest tumor's
  fold-80 went from 1.81 to 1.59. No normal metric changed: normal medians
  are 65-162, below the old cap.

---

## 2. QC background database (`scripts/qcdb/`)

New in this release (`bc0ed9f`, `7938777`, `80baecf`, `fa39938`,
`b493aa9`).

- `buildQCDb.R` (SLURM wrapper `runBuildQCDb.sh`, 8 cores, about 4 min for
  400 samples) reads HsMetrics, Alfred, Qualimap, fastp, Conpair, Tempo
  QC status, FACETS, `sample_data.txt`, the final and unfiltered MAFs and
  Manta, and writes `qcdb/qcdb_<assay>_<yymmdd>.rds`. The tables: wide
  and long metrics per sample and pair, `reference` (per metric and type:
  N, mean, SD, median, MAD and quantiles), per-target coverage summaries,
  distributions, Nextflow resource use, completeness and a column
  dictionary. HsMetrics come from `post/qc` by default (`--hsmetrics=DIR`
  to change); the folder and cap are recorded in `meta`.
- The `.rds` files are not in git. `assets/qcdb/qcdb_index.tsv` lists
  each one (assay, version, date, path), and
  `scripts/qcdb/rsrc/qcdb_index.R` finds and loads the newest version for
  an assay (`find_qcdb()`, `load_qcdb()`).
- First database: WES IDT v2, 200 tumor/normal pairs picked to be typical
  in data size (195 FFPE tumors, 198 blood normals). Version `261122`
  used Tempo's capped HsMetrics; version `261123` uses the 1000x files
  and is the current one.

No report uses the database yet; it is the input for a new QC report.

---

## 3. Missing samples and pairs (#6)

- `scripts/bic2tempo.R` and `scripts/fastq2tempo.R` stop and name the
  sample on bad input: a pair with a sample not in the mapping (including
  an `na` normal), a sample with no R1 files, R1 and R2 files that do not
  pair up, a sample missing from the target manifest, or an R1 name
  without `_R1_NNN.fastq` (`0fb6e93`).
- `scripts/checkPairOutputs.R` with `scripts/rsrc/check_pairs.R` checks
  that every pair in the pairing file has the output of each workflow and
  writes `out/<ID>/runlog/pair_check.txt`. The run scripts call it last
  and exit 3 if a pair is missing output, so SLURM reports the job as
  failed (`17218a4`).
- The SNV, FACETS and FACETS QC reports add a `MissingPairs` sheet, and
  the QC PDF a last page, when a pair is missing (`8fcc66e`). The WES
  reports now need exactly one `out/*/runlog/cmd.sh.log`, as the WGS
  reports already did.

---

## 4. Delivery (`bin/deliver.sh`, `bin/deliverGermline.sh`)

- `-n` dry run: prints the `dzdo` and permissions-database commands
  instead of running them; the email and `project.yaml` are still written
  (`4f0ab84`).
- `-r` skips the FACETS files (`*facets*` and Tempo's cohort `cna_*`).
  The MAFs, `sample_data.txt`, MultiQC and the SNV and All reports keep
  their FACETS columns (`c3b6edd`).
- Every delivered file gets group `grp_hpc_core001`, every folder is
  group-writable with setgid, and macOS `._*` files are not delivered
  (`ecf75a8`, `337d16d`).
- The email is rewritten: one line per main report, `{FACETS}` lines
  dropped with `-r`, `{WGS}` lines kept only for genome runs, one line per
  paragraph. The file is `deliveryEmail_<no>_<r_NNN>_<yymmdd>.txt` and
  uses the project number without `Proj_` (`725900f`, `92047d2`,
  `6f33dcc`).

---

## 5. Other fixes

- Report names: `reportFacets01.R` wrote `Proj_Proj_` names for a `Proj_`
  ID (#13, `ae85113`); the TERT, germline, germline SV and multi-SV
  reports now also name files `Proj_<ID>_...` (`9ca8cd8`).
- The `Script:` line in `cmd.sh.log` logs all options, and
  `reportGerm01.R` reads the normals with `read_pairing()` instead of the
  5th field of that line (#15, `bd67147`).
- Run script usage text: `runTempoWESCohort.sh` no longer lists `sv` or
  `germsv` (WGS only); `runTempoWGSBam.sh` named itself
  `runTempoWGSBams.sh` and now writes `<ID>_runTempoWGSBam.log` (#15,
  `d31c928`).
- A failed trace report prints a WARNING. The WGS trace report ran in the
  scratch `WORKDIR` and always failed; fixed. `nfTraceReport.R` checks its
  R packages before loading them (#22, #12, `5fafdac`).
- `report01.R` read the portal gene-frequency file through
  `/home/soccin`, which other users cannot enter (`9f1a367`).
- `qcReport01.R` showed an extra "R" facet in the HS metrics plot
  (`c992789`).

---

## 6. JUNO removed (#16, `45b6e8a`)

JUNO was shut down on 2026-10-01. Removed: `conf/*juno*.config`, the JUNO
branches in the run scripts, the subnet test in `getClusterName.sh`, JUNO
in `get_cluster_name.R` and `report01.R`, and `scripts/resume00.sh`.
`docs/JUNO_LSF.md` is kept as a record. Tempo's `iris` profile still loads
`tempo/conf/juno.config` and the `resources_juno*.config` files; those are
Tempo code and IRIS needs them.

---

## 7. Tempo submodule

No change: still `a7ecd35a` on `devs-iris`.

---

## 8. Documentation

- Bugs and planned work moved to GitHub issues; `00.FIXME.txt` lists only
  critical open bugs; `notes/` moved into `devs/` (`de45267`, `fce1549`,
  `a1c1a85`, `e8c5450`).
- `CLAUDE.md`: `deliver.sh` options, delivery group, email template tags
  and report versions; the missing-pair checks; `SLM/` is created by
  SLURM, `sbatch` does not need it (#20); the HsMetrics rerun and the QC
  database (`a95f5b6`, `a122523`, `8c6f10b`, `a057946`, `56391ab`,
  `080d07f`, `51715bd`, `b2c0586`, `8e7ba37`).
- IRIS config comments: no version stamp, correct headers, the SvABA
  comment matches the settings, `cmobic_cpu` is 14 x 56-core and 5 x
  96-core nodes (#18, `c48d9ba`).
- `README.md`: the pair check and the HsMetrics step in the resume notes;
  a WES HsMetrics section (`8c9f063`, `b096bee`).
- `docs/methods.md`: the 1000x HsMetrics rerun. `docs/output.md`: the
  `post/qc` folder; html and pdf rebuilt (`8e7ba37`, `b096bee`).
- `scripts/hsmetrics/README.md` and `scripts/qcdb/README.md`: new.

---

## 9. Resource settings seen in a live WES run (#24)

The 200-pair WES background run (2026-11-22, 7h10m, on `master` at
`f9fde04`, with the v3.2.2 WES config) finished with every pair complete.
42 tasks hit the 2 h walltime: 39 `AlignReads` (6% of 609) and 3
`QcQualimap`. All completed on the retry at the next tier. `AlignReads`
peaked at up to 146 GB RSS (median 40 GB). No task failed in the end.

---

## 10. Known issues open at release

- **Critical** (`00.FIXME.txt`): ClusterSV crashes on samples with many
  SVs, which then have no SV clustering (#5); `filter_regions_bedpe.py`
  reports an OOM as zero overlaps, so the SV report is delivered
  unfiltered (#7).
- **CohortRunMultiQC fails on BAM-input WGS runs** (#8), and its
  `coverage_split.txt` join drops pairs (#9).
- **A WGS `doPost.sh` stops early if there are no WGS metrics** (#10).
- **CrossValidateSamples drops pairs silently** and matches IDs by
  substring (#28).
- **The `doHsMetrics.sh` call in `runTempoWESCohort.sh` has not run in a
  live pipeline yet.** The script itself ran on all 400 samples by hand.
  On the first WES run, check that the array is submitted at the end of
  the run log.

---

## 11. Upgrade notes

- IRIS only. No submodule change.
- WES runs: the run job ends before the HsMetrics array does. Wait for
  the `HsMetrics` jobs (`squeue -u $USER -n HsMetrics`) before
  `deliver.sh`, so `post/qc` is delivered.
- Runs from before v3.2.3: run
  `<adagio>/scripts/hsmetrics/doHsMetrics.sh -p <PROJECT_ID>` from the
  project folder to get the uncapped files.
- A manual nextflow resume skips the post-run steps; run the pair check
  and `doHsMetrics.sh` by hand (see `README.md`).
- Reports read the QC database through the index; add each new build's
  line (printed at the end of the build) to
  `assets/qcdb/qcdb_index.tsv`.
