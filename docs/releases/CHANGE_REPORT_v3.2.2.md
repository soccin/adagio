# Adagio v3.2.2 Change Report

Changes from v3.2.1 (2026-10-02) to v3.2.2 (2026-10-03).

---

## Overview

v3.2.2 is a patch release on the **Cordelia** line: 24 non-merge commits
since v3.2.1, not counting the release documentation. The tempo submodule
is unchanged at `a7ecd35a`; only its tracking branch name changed, from
`devs/iris` to `devs-iris`. IRIS is the only supported cluster. The JUNO
code paths are still dead and were not changed.

Headline items:

1. **Combined SV/SNV/CNV report** (`reportAll.R`) for WGS, run by
   `doPost.sh`, with a plain-language description delivered alongside it.
2. **One definition of the FACETS rules** (`scripts/rsrc/facets_rules.R`).
   All four reports that use FACETS results now apply the same sample rule
   (`facets_qc` or `|dipLogR| < 0.5`) and focal rule (segment <= 1 Mb).
3. **WES IRIS right-sizing**, the work deferred from v3.2.1: the
   QcQualimap OOM fix and smaller requests for the oversized blocks.
4. **Delivery as a service account**, and a delivery email filled from the
   run.
5. **Shared Excel writers**: every workbook opens at 150% zoom with a fixed
   window size.

---

## 1. Reporting (`scripts/`)

### 1a. Combined report (`reportAll.R`, output `*_All_Report01_v2.xlsx`)

New in this release (`93e317e`, `b119c44`, `bbac46b`, `9c1afe5`). One
workbook with four sheets:

- **SampleSummary**: one row per tumor in the pairing file: SV, SNV,
  loss-of-function SNV and focal CNV counts, total mutations, WGD, and the
  FACETS values.
- **GeneRanking**: genes ranked by the number of tumors with any SV, SNV
  or CNV event, each tumor counted once, split by type and CNV direction.
- **SVFreq_HV**: SV gene pairs in at least 5% of tumors, with the in-frame
  fusion count, median breakpoint distance and chromosome bands.
  Single-tumor pairs are kept only with an in-frame fusion call.
- **ColDescriptions**: the rule behind every column.

Event rules: same-chromosome SVs under 1 Mb are dropped on every sheet;
SNVs follow the SNV report (non-synonymous plus the TERT promoter rescue);
a CNV event is a FACETS gene-level call with filter PASS or RESCUE on a
focal autosomal segment, from a sample that passes the sample rule.

`bin/doPost.sh` runs it for WGS after `getWGSStats.R` and copies
`docs/DESCRIPTION_ALL_REPORT.md` into `post/reports`. Bands come from the
new `scripts/rsrc/cytoBand_hg19.txt.gz` (UCSC). The output is v2: v1 was
never released.

### 1b. FACETS rules in one file (`5da458c`, `f47b97d`, `5403f36`, `2c26e73`)

`scripts/rsrc/facets_rules.R` defines `max_abs_diplogr = 0.5`,
`max_focal_seg_length = 1e6`, `facets_sample_pass()` and `is_focal_seg()`.
`report01.R`, `qcReport01.R`, `reportFacets01.R` and `reportAll.R` source
it. The thresholds are locked with `lockBinding()`, so a report script
cannot reassign them. `scripts/rsrc/test_facets_rules.R` tests both rules
at and around the thresholds and with missing values.

During development the gate was briefly 1.5 (`935bb51`, `5da458c`). It
was set back to 0.5 before release (`5403f36`): across 688 FACETS results,
1.5 removed only 4 extreme outliers while 0.5 also removes 53 QC failures.
The released gate is the same as in v3.2.1.

Effect on each report:

| Report | Change | Output |
|---|---|---|
| SNV (`report01.R`) | Ploidy and FGA blanked by the sample rule, not by `facets_qc` alone; fewer blanks | `*_SNV_Report01_v4.xlsx` (was v3) |
| FACETS QC (`qcReport01.R`) | `facetsFailedSamples` written from the sample rule | `*_facetsQCRpt_v1.xlsx` (content unchanged) |
| FACETS (`reportFacets01.R`) | Rules read from the shared file; a missing `facets_qc` now counts as a failure; `--help` prints the gate | `*_facets_v5.xlsx` (was v4) |
| Combined (`reportAll.R`, new) | Uses both rules; Ploidy and FGA blanked for samples that fail the sample rule | `*_All_Report01_v2.xlsx` |

This fixes a case where a sample was kept in the FACETS report but had
blank ploidy and FGA in the SNV report.

### 1c. Shared Excel writers (`bbac46b`)

- `scripts/rsrc/xlsx_report.R`: the openxlsx2 writer that `reportSV01.R`
  carried, now shared with `reportAll.R`.
- `scripts/rsrc/xlsx_legacy.R`: `finalize_xlsx()` and
  `write_xlsx_report()` for the openxlsx scripts.
- `scripts/rsrc/xlsx_defaults.R`: zoom 150% and the window size. Without
  an explicit window size, Excel for Mac opens the file full screen.

Switched to the shared writers: `report01`, `reportSV01`, `reportAll`,
`reportFacets01`, `qcReport01`, `getWGSStats`, `reportTERT`, `reportGerm01`,
`reportGermSV01`, `multiSVReport01`, `nfTraceReport`. The `set_zoom` 120%
code in `report01.R` and `reportGerm01.R` is removed.

---

## 2. IRIS WES configuration (`conf/tempo-wes-iris.config`)

Sized from the traces of 9 WES runs (2025-10 to 2026-09), following
`devs/wes-iris-work-plan.md` (`c0cfd2b`). Memory is about 1.5-2x the
measured peak RSS and doubles on retry. Every block finished in under
0.6 h, inside the 2 h short queue. Time lines are unchanged.

| Process | Before | v3.2.2 |
|---|---|---|
| `QcQualimap` | `4 * attempt` cpus, `128.GB + 128.GB * attempt` | 3 cpus, `4.GB * attempt`, explicit `--mem` = cpus x memory x 1.1 |
| `DoFacets` | `4 + 12 * attempt` cpus, `246.GB * attempt` | 2 cpus, `16.GB * attempt` |
| `multiqc_process` label | `4 + 12 * attempt` cpus, `34.GB * attempt` | 2 cpus, `2.GB * attempt` |
| `SomaticAnnotateMaf` | `4 + 12 * attempt` cpus, `34.GB * attempt` | 2 cpus, `8.GB * attempt` |
| `SomaticFacetsAnnotation` | `4 + 12 * attempt` cpus, `34.GB * attempt` | 2 cpus, `2.GB * attempt` |
| `SomaticRunManta`, `SomaticRunStrelka2`, `GermlineRunStrelka2` | `4 + 12 * attempt` cpus, `246.GB * attempt` | 8 cpus, `4.GB * attempt` |
| `SomaticCombineChannel`, `GermlineCombineChannel` | `4 + 12 * attempt` cpus, `246.GB * attempt` | 2 cpus, `8.GB * attempt` |
| `MetaDataParser` | `4 + 12 * attempt` cpus, `246.GB * attempt` | 2 cpus, `2.GB * attempt` |
| `CohortRunMultiQC` | `4 + 12 * attempt` cpus, `246.GB * attempt` | 2 cpus, `64.GB * attempt` |

QcQualimap (`250ae33`): Tempo sets the Qualimap JVM heap to cpus x memory
(the JUNO per-core model). IRIS has `mem_per_core = false`, so SLURM was
given only `memory`, and 80 of 241 WES tasks were OOM-killed (exit 137).
The new block requests the heap Tempo hands the JVM through `--mem` and
keeps `qosFor(task)`. Attempt 1 gives an 11 GB heap, the heap 126 WES
tasks completed on under JUNO (peak RSS 7.9 GB, max 0.57 h).

The blanket blocks (`23bd930`) requested 16 cpus and 34 or 246 GB
for tasks that peak at a few GB. In a 249-pair germline cohort, the 246 GB
requests let only 236 tasks run at once under the 58 TB QoS memory cap.
`SomaticRunManta` is part of `snv` (candidate indels for Strelka2), not SV.
The SV-only blocks, SplitLanes and HaplotypeCaller are unchanged.

The config header no longer says "WGS specific options" (`6f7fdbe`).

Not yet tested on a live WES run; see section 6.

---

## 3. Delivery (`bin/deliver.sh`, `bin/deliverGermline.sh`)

- All `mkdir` and `rsync` writes to the delivery area run as
  `svc_core001_bot01` through `dzdo`, so the delivered files belong to the
  service account (`2ab1ebd`).
- The email (`assets/delivery_email_template.txt`) now has a subject line,
  the actual `r_NNN` folder, and a docs link at the release tag the run was
  built from, parsed from `GTAG` in `cmd.sh.log`. It used to link a fixed
  `r_001` folder and the v3.0.0 docs (`3981355`). If `GTAG` cannot be
  parsed, the link reads `UNKNOWN` and the script prints a warning.

---

## 4. Tempo submodule

No commit change: still `a7ecd35a`. `.gitmodules` tracks branch
`devs-iris` (was `devs/iris`); the commit is on both `origin/devs-iris` and
`origin/devs/iris` (`e05c0b5`).

---

## 5. Documentation

- `docs/output.md` rewritten for v3.2.2, with `docs/output.html` and
  `docs/output.pdf` rebuilt (`818f707`, `ca4a15f`). The delivery email
  links to it at the release tag and attaches the PDF.
- `docs/methods.md` rewritten for v3.2.2 (`4eb0599`).
- `docs/DESCRIPTION_ALL_REPORT.md` new (`9c1afe5`) and matched to
  `reportAll.R` (`584498d`).
- `docs/DESCRIPTION_FOCAL_GENES.md` and `docs/METHODS_CNV_GENES.md`:
  report versions, the 0.5 gate, the WGD source and the filter owner
  (`293ab40`, `7654bd7`, `06b17de`).
- Dead Tempo develop docs link replaced in `README.md` and
  `docs/pipeline.md` (`bdc2e9d`).

Release review of every tracked markdown file:

- `README.md`: version; link to `docs/install.md`; the Resume section
  replaced. The old one used JUNO paths and did not resume on IRIS, where
  each run has its own scratch `WORKDIR`.
- `CLAUDE.md`: version; entry points, reports and `rsrc/` contents;
  environment; resume and cleanup steps; retry counts; install through
  `00.SETUP.sh`.
- `docs/install.md`: the Nextflow 25.10.4 pin.
- `docs/output.md`: fastp is WES only; signatures are in
  `sample_data.txt`; `runlog` contents; the geneLevelFocal direction
  rule; `frac_homdels`; `README_NoSVs.txt`. html and pdf rebuilt.
- `docs/methods.md`: WGS BAMs come from SMap, WES BAMs from Tempo; TMB
  definition; caller-PASS union; gnomAD popmax.
- `docs/DESCRIPTION_ALL_REPORT.md`: SampleSummary column order, `Pct`,
  `genePair`, INDETERMINATE calls.
- `docs/DESCRIPTION_FOCAL_GENES.md`: worked example made consistent.
- `docs/IRIS_SLURM.md`: node counts re-checked (269 nodes under 2 h, was
  270); the cmobic partitions include 96-core `isco` nodes.
- `TODO.md`, `devs/wes-iris-work-plan.md`,
  `devs/wes-iris-parity-report.md`, `devs/patches/README.md`,
  `scripts/rsrc/nf-reports/README.md`: status brought up to date.

---

## 6. Known issues open at release

- **WES right-sizing not yet run live.** Watch the first WES run on
  v3.2.2 for exit 137 in QcQualimap, DoFacets and CohortRunMultiQC.
- **CohortRunMultiQC fails on BAM-input WGS runs**; unchanged from v3.2.1.
  See `bugs/BUG_REPORT_CohortRunMultiQC.md` and `00.FIXME.txt`.
- **WGS driver runs `nfTraceReport.R` in the scratch `WORKDIR`**, where
  there is no `out/`, so the WGS trace report fails. The WES driver and
  `makeTempoBams.sh` use `pushd`/`popd`.
- **A WGS `doPost.sh` stops early if there are no WGS metrics.**
  `getWGSStats.R` exits 1 when no `wgs.txt` files exist, and `doPost.sh`
  runs with `set -eu`, so `reportAll.R`, `output.html` and `version.txt`
  are not produced.
- `filter_regions_bedpe.py`, ClusterSV and the SvABA review items are
  unchanged from v3.2.1 (see its section 7).

---

## 7. Upgrade notes

- IRIS only, as in v3.2.1.
- Update with submodules: `git submodule sync` then
  `git submodule update --init`, so the clone picks up the `devs-iris`
  branch name.
- New and changed output names: `*_SNV_Report01_v4.xlsx`,
  `*_facets_v5.xlsx`, `*_All_Report01_v2.xlsx` (WGS, new).
- `deliver.sh` and `deliverGermline.sh` need `dzdo` rights to run as
  `svc_core001_bot01`.
- To change a FACETS threshold, edit only `scripts/rsrc/facets_rules.R`,
  run `test_facets_rules.R`, and follow the checklist in its header.
