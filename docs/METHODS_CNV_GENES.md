# Methods: geneLevelFocal sheet of the FACETS report

This document describes how the `geneLevelFocal` sheet of the FACETS copy
number report is built, in enough detail to reproduce it.

- Report: `post/reports/Proj_<project>[_NO_FILT]_facets_v4.xlsx`, sheet
  `geneLevelFocal`
- Script: `scripts/reportFacets01.R`
- Resource file: `scripts/rsrc/centromeres_<genome>.tsv`

The sheet has one row per gene. A gene is included if, in at least one
sample, it lies on a small (focal) copy number segment and that segment's
copy number is not 2. The row then summarizes the calls at that gene across
the whole cohort.

## 1. Upstream data

### 1.1 Copy number calling

Copy number is called by the Tempo pipeline (`DoFacets` process) with the
facets-suite wrappers around FACETS. Each tumor/normal pair is run twice:
a purity pass and a high-sensitivity (hisens) pass. The parameters used for
a run (FACETS version, genome, cval, purity_cval, snp.nbhd, ndepth,
min.nhet) are recorded in the report's `facetsParams` sheet.

facets-suite (`gene_level_changes()`, version 2.0.8 in the Tempo
container) writes a per-sample `*.gene_level.txt` file. Each row is one
gene in one sample and gives the segment the gene lies on, the segment's
integer total copy number (`tcn`), lesser (minor) copy number (`lcn`), and
facets-suite's copy number state label (`cn_state`).

The gene-level calls come from the **hisens** fit
(`run-facets-wrapper.R` calls `gene_level_changes(hisens_output)`; the
arm-level file uses the purity fit). The (sample, chrom, seg_start,
seg_end) segments in the gene-level file match segments in the hisens
segmentation file, not the purity one (see section 8 to check this).

Gene table. facets-suite maps segments onto its built-in gene table for
the genome build: GENCODE v29 (the GRCh37 lift for hg19), genes annotated
`protein_coding`, with `gene_start`/`gene_end` the minimum start and
maximum end over the gene's records. `tsg` is TRUE if the symbol was
flagged as a tumor suppressor in OncoKB when facets-suite was built. A
gene appears in the file only if at least one pileup SNP lies inside it.
Each gene is assigned to one segment; `spans_segs = TRUE` marks genes
whose SNPs fall in more than one segment.

`cn_state` is looked up from (WGD status, `tcn`, `lcn`) in facets-suite's
`copy_number_states` table. WGD (whole-genome doubling) is TRUE when
segments with major copy number >= 2 cover more than half of the
autosomal genome; the same flag is the `wgd` column of the `facetsQC`
sheet. Combinations not in the table are `INDETERMINATE`, except
`tcn > 9`, which is `AMP`.

facets-suite `filter` column. Every row gets `PASS` unless one of these
applies (`max_seg_length = 1e7`, `max_gene_count = 10`,
`min_ccf = 0.6 * purity`):

| filter | Condition |
|---|---|
| `suppress_segment_too_large` | `cn_state` starts with `AMP` or is `HOMDEL`, and `seg_length > 1e7` |
| `suppress_likely_unfocal_large_gain` | `cn_state` starts with `AMP`, and none of: `tcn > 8`, `cf > min_ccf`, `genes_on_seg <= 10` |
| `suppress_large_homdel` | `cn_state` is `HOMDEL` and `genes_on_seg > 10` |
| `RESCUE` | Overrides a suppression when `cn_state` is `HOMDEL`, `tsg` is TRUE, and `seg_length < 1e7` |

Only `AMP*` and `HOMDEL` states can be suppressed. `GAIN`, `TETRAPLOID`,
`HETLOSS`, and all WGD-relative states always `PASS`.

### 1.2 Cohort aggregation in Tempo

Tempo's `SomaticAggregateFacets` process concatenates the per-sample files
into `out/<project>/cohort_level/default_cohort/cna_genelevel.txt` and keeps
only rows where (awk on columns 24 and 25 of the facets-suite file):

- `cn_state != "DIPLOID"`, and
- `filter` is `PASS` or `RESCUE`.

As a result, **the cohort file has no row for a gene in a sample where that
gene is diploid**, and no row for an `AMP*` or `HOMDEL` call that
facets-suite suppressed (section 1.1). A missing (sample, gene) pair is
treated as "no call" throughout this sheet. It is never counted as
neutral, and never in any numerator.

The second exclusion is not small. A sample with a whole-arm or
whole-chromosome amplification at `tcn >= 5` (non-WGD) or `tcn >= 6` (WGD)
loses every gene on that segment, because the segment is longer than
10 Mb. In one WGS cohort, one sample had 13,423 of its 19,830 gene rows
removed this way. Broad `GAIN` calls (`tcn` 3-4 non-WGD, 5 WGD) are never
suppressed, so `pct_amp` includes broad low-level gains but generally
excludes broad high-level amplifications. The focal calls that qualify a
gene for the sheet are 1 Mb or shorter and so pass the length filter, but
a focal `AMP` can still be suppressed by the
`suppress_likely_unfocal_large_gain` rule if `tcn <= 8`, the segment's
cellular fraction is low, and the segment holds more than 10 genes.

Columns used from `cna_genelevel.txt`: `sample`, `gene`, `chrom`,
`gene_start`, `gene_end`, `tsg`, `seg_length`, `tcn`, `cn_state`.
`seg_length` equals `seg_end - seg_start`. `chrom` is numeric with X coded
as 23; `sample` is `<TUMOR>__<NORMAL>`.

## 2. Sample set

The cohort is all tumor samples that pass the report's sample filter.
The filter is read from each sample's `*.facets_qc.txt`, written by
Tempo's `DoFacetsPreviewQC` process (facets-preview
`generate_genomic_annotations()`): a sample passes if `facets_qc` is
TRUE, or if `|dipLogR| < 0.5`. A missing `dipLogR` does not rescue a
sample with `facets_qc` FALSE. Samples that fail are removed from the
gene-level data before any step below. `--keep-failed` disables the
filter (output files are then tagged `NO_FILT`).

`N_cohort` is the number of distinct `tumor_sample_id` values that pass the
filter. It comes from the QC files, not from the gene-level file, so a
sample with no calls at all still counts in the denominator. Note that
`tumor_sample_id` is the `<TUMOR>__<NORMAL>` pair ID, so a tumor paired
with two normals would count twice (see section 8).

## 3. Processing steps

Constants:

- `max_focal_seg_length = 1e6` (1 Mb, inclusive)
- `N_cohort` as defined in section 2

Steps, in order:

1. **Autosomes only.** Map chromosome names to numbers: strip a leading
   `chr`, X -> 23, Y -> 24 (the input is already numeric with X = 23; the
   mapping also accepts `chrX`-style names). Drop every row with
   chromosome > 22. X copy number cannot be called accurately without
   the sample's sex, which is usually not available.
2. **Chromosome arm.** Join the centromere table for the run's genome
   (read from the FACETS `genome` parameter). `arm = <chrom>p` if
   `gene_start < centromere`, else `<chrom>q`.
3. **Sample IDs.** Shorten `TUMOR__NORMAL` to `TUMOR` (remove `__` and
   everything after it).
4. **Focal flag.** `focal = seg_length <= 1e6`.
5. **Order.** Sort rows by the shortened sample ID in byte (C-locale)
   order, which is `dplyr::arrange()`'s default: digits before upper
   case before lower case. Every per-sample list in the output uses this
   order.
6. **Group** by gene (with arm, tsg, chrom, gene_start, gene_end, which are
   constant within a gene).
7. **Gene filter.** Let `S` be the set of values `sign(tcn - 2)` over the
   gene's focal calls with `tcn != 2`. Keep the gene only if `S` contains
   exactly one value. This is two conditions:
   - at least one focal call has `tcn != 2`, and
   - all focal calls with `tcn != 2` point the same way: all gains
     (`tcn > 2`) or all losses (`tcn < 2`).

   Focal calls with `tcn == 2` do not count toward either condition. They
   neither qualify a gene nor disqualify it. Non-focal calls are not
   checked, so a gene with focal gains can have non-focal losses.

   The check assumes `tcn` is never NA (section 8). An NA `tcn` would be
   counted by `n_distinct()` as a distinct value and would also make the
   percentage columns NA.
8. **Summarize** each kept gene (see section 4). All counts and
   percentages use **all** of the gene's calls, focal or not, except the
   `*_focal` columns.
9. **Sort** rows by chromosome number, then `gene_start`, then `gene`.

## 4. Output columns

| Column | Definition |
|---|---|
| `gene` | Gene symbol from the facets-suite gene table (section 1.1). |
| `arm` | Chromosome arm of `gene_start` (e.g. `7q`), step 2. |
| `samples_focal` | Comma-separated (no space) shortened sample IDs with a focal call at the gene (includes focal `tcn == 2` calls). Step 5 order. |
| `samples_all` | Comma-separated shortened sample IDs with any call at the gene, any segment size. Step 5 order. |
| `n_focal` | Number of samples in `samples_focal`. |
| `n_all` | Number of samples in `samples_all`. |
| `pct_loss` | `round(100 * #calls with tcn < 2 / N_cohort)` |
| `pct_cnloh` | `round(100 * #calls with tcn == 2 / N_cohort)` |
| `pct_amp` | `round(100 * #calls with tcn > 2 / N_cohort)` |
| `cn_state_summary` | facets-suite `cn_state` for each sample in `samples_all`, same order, `;`-separated (no space). A trailing `+` marks a focal call. |
| `tcn_summary` | `tcn` for each sample in `samples_all`, same order, `;`-separated, `+` marks a focal call. |
| `chrom` | Chromosome number (1-22), as in the input file. |
| `gene_start`, `gene_end` | Gene coordinates, in the run's genome build, from the gene-level file. |
| `tsg` | facets-suite tumor suppressor gene flag (OncoKB, section 1.1). |

Properties that hold for every row by construction:

- `pct_loss + pct_cnloh + pct_amp` is approximately `100 * n_all / N_cohort`
  (off by rounding only). It is below 100 whenever some samples have no
  call at the gene.
- The number of `+` marks in `tcn_summary` equals `n_focal`.
- `n_focal >= 1`.

Percentages are rounded to whole numbers with R's `round()` (round half to
even).

## 5. Chromosome arm boundaries

`rsrc/centromeres_hg19.tsv` gives one boundary per chromosome: the end of
the last p band in the UCSC hg19 cytoBand table (the p11.1/q11.1
boundary, i.e. the middle of the centromere band). The table was taken
from the copy that ships with the `circlize` R package
(`system.file("extdata", "cytoBand.txt", package = "circlize")`), whose
chr1 length (249,250,621) confirms it is hg19. Chromosomes are numbered in
FACETS style (X = 23, Y = 24).

facets-suite's own arm-level code splits segments at a different
position: the start of the centromere gap from the UCSC hg19 gap table
(its internal `hg19$centromere`; chr2: 92,326,171 versus 93,300,000
here). The two definitions give the same arm for every gene, for two
reasons. For every chromosome except chr1 the cytoBand p/q boundary lies
inside the facets-suite gap interval, and the gap contains no genes. For
chr1 the boundary (125.0 Mb) is 465 kb past the gap end (124.5 Mb), and
no gene in facets-suite's hg19 gene table starts in that interval. So
`arm` here agrees with the `armLevel` sheet for all genes. Re-check this
if either table changes (section 8).

The script reads the file named after the FACETS `genome` parameter. A run
on another genome build stops with a file-not-found error until the
matching file (e.g. `centromeres_hg38.tsv`) is added. To build one, take
the maximum end coordinate of the p bands per chromosome from that build's
UCSC cytoBand table and write the same two columns (`chrom`, `centromere`).

A gene that crosses the boundary gets the arm of its `gene_start`.

## 6. Interpretation caveats

These follow from the definitions above and should be kept in mind when
using the sheet.

- **Thresholds use absolute copy number.** Loss, CNLOH, and gain are set
  by `tcn` relative to 2, not relative to sample ploidy. In a
  genome-doubled sample (`wgd` TRUE in the `facetsQC` sheet), every
  `tcn = 3` and `tcn = 4` state is a gain here even though facets-suite
  scores all of them except `TETRAPLOID` as losses relative to the
  doubled genome:

  | cn_state (WGD) | tcn | lcn | facets-suite call | here |
  |---|---|---|---|---|
  | `CNLOH BEFORE & LOSS` | 3 | 0 | loss | gain |
  | `LOSS AFTER` | 3 | 1 | loss | gain |
  | `LOSS (many states)` | 3 | NA | loss | gain |
  | `CNLOH BEFORE` | 4 | 0 | loss | gain |
  | `CNLOH AFTER` | 4 | 1 | loss | gain |
  | `TETRAPLOID` | 4 | 2 | neutral | gain |
  | `TETRAPLOID or CNLOH BEFORE` | 4 | NA | loss | gain |

  A gene can be on the sheet only because of such a call.
  `cn_state_summary` is provided so each call can be read in its ploidy
  context. In a non-WGD sample `TETRAPLOID` (`tcn = 4`, `lcn = 2`) is a
  true balanced two-copy gain and is often the most common focal
  qualifying state.
- **`pct_cnloh` counts every `tcn == 2` call**, not only calls with loss of
  heterozygosity. The complete list of facets-suite states with
  `tcn == 2` (other than `DIPLOID`, which is never in the file) is:

  | cn_state | WGD | lcn |
  |---|---|---|
  | `CNLOH` | no | 0 |
  | `DIPLOID or CNLOH` | no | NA (LOH not resolved) |
  | `LOSS BEFORE` | yes | 0 |
  | `DOUBLE LOSS AFTER` | yes | 1 (not LOH) |
  | `LOSS BEFORE or DOUBLE LOSS AFTER` | yes | NA |

- **Broad high-level amplifications and homozygous deletions are
  missing.** facets-suite suppresses `AMP*` and `HOMDEL` calls on
  segments over 10 Mb or with many genes, and Tempo drops suppressed rows
  (sections 1.1, 1.2). Such a sample contributes nothing to `pct_amp` or
  `pct_loss` at those genes and is absent from `samples_all`. Broad
  `GAIN` and `HETLOSS` calls are not suppressed, so the two percentages
  are not symmetric in what they omit.

- **Focal is a segment property.** A gene is focal in a sample if the
  whole FACETS segment containing it is 1 Mb or shorter. Segment ends
  depend on SNP density and on the hisens `cval`, so a gene may be focal
  in one sample and part of a large segment in another.
- **Diploid samples are invisible.** Because Tempo drops `DIPLOID` rows,
  the sheet cannot distinguish a diploid sample from one whose call was
  suppressed by the facets-suite filter, or from one where the gene had no
  SNP coverage. All are "no call".
- **One call per sample per gene.** The method assumes the gene-level file
  has at most one row per (sample, gene). See section 8.
- **Focal segments are hisens segments.** Segment boundaries, and so the
  focal flag, come from the hisens fit (`cval` in `facetsParams`), which
  segments more finely than the purity fit used for the `armLevel` sheet.

## 7. Related behavior in the armLevel sheet

The `armLevel` sheet also drops chromosome X (arms `23p`, `23q`, and any
X/Y-labeled arms) for the same reason as step 1, and is sorted by sample,
then chromosome number, then p before q.

## 8. Checks for a new project

The method relies on these properties of the input. Check them when
running on a new project or a new Tempo/facets-suite version:

- **Calls come from the hisens fit.** Every distinct (sample, chrom,
  seg_start, seg_end) in `cna_genelevel.txt` should match a segment in the
  hisens `.seg` file (`cna_hisens_run_segmentation.seg`).
- **No diploid rows.** `cn_state` should never be `DIPLOID`, and `filter`
  should only be `PASS` or `RESCUE`.
- **No NA `tcn`.** `sum(is.na(tcn))` should be 0. (`lcn` is often NA;
  that is expected.)
- **One row per (sample, gene).** `count(sample, gene)` should never
  exceed 1.
- **One pair per tumor.** Each tumor should appear in exactly one
  `<TUMOR>__<NORMAL>` pair. A tumor run against two normals would be
  counted twice in `N_cohort` and would appear twice, under the same
  shortened ID, in the summary columns.
- **Constant gene annotation.** `chrom`, `gene_start`, `gene_end`, and
  `tsg` should be the same for every row of a gene.
- **Genome build.** The FACETS `genome` parameter should have a matching
  `rsrc/centromeres_<genome>.tsv`, and no gene should start between that
  file's boundary and facets-suite's centromere start for the same build
  (section 5).

## 9. Reproducing

From the project directory (the one containing `out/`):

```bash
Rscript <adagio>/scripts/reportFacets01.R
```

`bin/doPost.sh` also runs it as part of the full post-processing step.

Requires R with `tidyverse`, `readxl`, and `openxlsx` (last verified with
R 4.5.1 and dplyr 1.2.1). The script uses `get_script_dir()`, defined in
the user's `~/.Rprofile`, to locate `rsrc/`. The `facetsParamCols` file
in `rsrc/` lists the run-info columns moved to the `facetsParams` sheet;
it must include `genome`.

The focal gene logic is in the "Focal gene-level summary" section of the
script. A minimal re-implementation needs only `cna_genelevel.txt`, the
list of passing samples, and the centromere table, and follows steps 1-9
of section 3.
