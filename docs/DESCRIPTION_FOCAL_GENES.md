# Guide to the geneLevelFocal sheet

## Summary

The `geneLevelFocal` sheet lists genes that are gained or lost on a small
genomic segment (1 Mb or shorter) in at least one tumor. Small changes are
more likely to target a specific gene than changes covering a whole
chromosome arm. A gene is kept only if its focal changes all go the same
direction: all gains or all losses. Chromosome X is excluded because
patient sex is usually not known. For each gene, the sheet lists the tumors
with a focal change, the tumors with any change, and the percentage of the
cohort with a loss, a copy-neutral loss of heterozygosity (CNLOH), or a
gain. Copy number is not adjusted for whole-genome doubling, so check the
FACETS state of each gain before interpreting it.

This guide explains the `geneLevelFocal` sheet in the FACETS copy number
report (`Proj_<project>_facets_v4.xlsx`). It is written for readers who
use the results, not for those who compute them. The technical method is in
`METHODS_CNV_GENES.md`.

## What the sheet shows

The sheet lists genes that are gained or lost in a **small, focused region**
of the genome in at least one tumor. It then shows what happens to each of
those genes across all tumors in the cohort.

Small (focal) changes are of interest because they are more likely to be
selected for a specific gene than a change covering a whole chromosome arm,
which affects hundreds of genes at once.

## Key terms

**Copy number.** Normal human cells carry two copies of each autosome
(chromosomes 1-22), so most genes are present in two copies. Tumors often
gain or lose copies of parts of the genome.

**Total copy number (tcn).** The number of copies of a gene in the tumor,
as estimated by FACETS. A value of 2 is the normal count.

- **Loss:** tcn below 2 (1 copy, or 0 copies = deletion).
- **Gain / amplification:** tcn above 2. The column is named `pct_amp`,
  but it counts any gain, including modest ones of 3 or 4 copies. FACETS
  reserves the label `AMP` for 5 or more copies (6 or more in a
  genome-doubled tumor); `cn_state_summary` shows which label applied.

**CNLOH (copy-neutral loss of heterozygosity).** The tumor still has two
copies of the gene, but both come from the same parent. The gene count is
normal, but one parent's version of the gene is gone. In this sheet, any
non-normal call with tcn exactly 2 is grouped under CNLOH (see the cautions
below).

**Segment.** FACETS divides each tumor's genome into stretches (segments)
that have the same copy number. Every gene lies on one segment.

**Focal.** A change is called focal if the segment carrying it is
**1 million bases (1 Mb) or shorter**. For scale, chromosome 1 is about
249 Mb long.

**Chromosome arm.** Each chromosome has a short arm (p) and a long arm (q),
separated by the centromere. `7q` means the long arm of chromosome 7.

## Which genes are included

A gene is listed if all of the following are true:

1. It is on chromosomes 1-22. Chromosome X is left out because its copy
   number cannot be judged correctly without knowing each patient's sex,
   which is usually not available.
2. In at least one tumor, it lies on a focal segment (1 Mb or shorter)
   whose copy number is not 2.
3. If it is focal in more than one tumor, those focal changes all go the
   same direction: all gains, or all losses. Genes with a focal gain in one
   tumor and a focal loss in another are left out. Focal CNLOH (tcn = 2)
   changes are ignored for this rule, and so are changes on larger
   segments.

The genes considered are the protein-coding genes in the FACETS software's
built-in gene list (GENCODE version 29). A gene that has no sequenced
variant positions inside it is never evaluated and cannot appear.

Tumors that failed FACETS quality control are removed before the sheet is
built (a tumor is kept if it passed QC, or if its baseline log-ratio,
`dipLogR`, is within 0.5 of zero). The `runInfo` sheet lists the tumors
that were kept, with their `facets_qc` flag. A report run with the
`--keep-failed` option is named `..._NO_FILT_...` and keeps every tumor.

## Column guide

In this table, N is the number of tumors in the cohort after the quality
filter described above. Tumor names are the tumor sample ID alone; the
paired normal ID is dropped. Lists are separated by commas
(`samples_*`) or semicolons (`*_summary`) with no spaces, and every list
in a row uses the same tumor order.

| Column | Meaning |
|-------|------------------|
| `gene` | Gene name. |
| `arm` | Chromosome arm the gene is on (e.g. `7q`). |
| `samples_focal` | Tumors where the gene is on a focal segment (including focal CNLOH). |
| `samples_all` | Tumors with any copy number change at the gene, focal or not. |
| `n_focal` | How many tumors are in `samples_focal`. |
| `n_all` | How many tumors are in `samples_all`. |
| `pct_loss` | Percent of all N tumors with a loss at the gene (tcn below 2). |
| `pct_cnloh` | Percent of all N tumors with tcn = 2 and a non-normal state (mostly CNLOH). |
| `pct_amp` | Percent of all N tumors with a gain at the gene (tcn above 2). |
| `cn_state_summary` | The FACETS description of the change in each tumor listed in `samples_all`, in the same order. A `+` marks the focal ones. |
| `tcn_summary` | The copy number in each tumor listed in `samples_all`, in the same order. A `+` marks the focal ones. |
| `chrom` | Chromosome. |
| `gene_start`, `gene_end` | Gene position on the chromosome (in the genome build used for the run, shown in the `facetsParams` sheet). |
| `tsg` | TRUE if the gene is a known tumor suppressor gene. |

Rows are in genome order: chromosome 1 to 22, then by position.

### Why the three percentages do not add up to 100

Tumors in which the gene has the normal two copies (and both parents'
versions) are not counted in any of the three columns. The three
percentages add up to the share of tumors with some change at the gene,
which is `n_all` out of N. For example, if a gene is changed in 5 of 10
tumors, the three percentages add up to 50.

## Worked example

This example is made up to show how to read a row. The cohort has 10
tumors, TUMOR_01 to TUMOR_10.

| Column | Value |
|---|---|
| `gene` | GENE1 |
| `arm` | 7q |
| `samples_focal` | TUMOR_04 |
| `samples_all` | TUMOR_01,TUMOR_03,TUMOR_04,TUMOR_07,TUMOR_09 |
| `n_focal` | 1 |
| `n_all` | 5 |
| `pct_loss` / `pct_cnloh` / `pct_amp` | 10 / 10 / 30 |
| `cn_state_summary` | CNLOH;AMP (LOH);GAIN;AMP+;HETLOSS |
| `tcn_summary` | 2;5;3;7+;1 |

How to read it:

- GENE1 is on the long arm of chromosome 7.
- One tumor, TUMOR_04, has a focal change at GENE1: 7 copies (`7+`),
  labeled `AMP`. That focal amplification is why GENE1 is on the sheet.
- In total, 5 of the 10 tumors have some change at GENE1. Pair the lists
  position by position: TUMOR_01 has 2 copies (CNLOH), TUMOR_03 has 5
  copies, TUMOR_04 has the focal 7 copies, TUMOR_07 has 3 copies, and
  TUMOR_09 has 1 copy (a loss). Only the TUMOR_04 change is focal; the
  others lie on larger segments.
- The loss in TUMOR_09 does not remove GENE1 from the sheet, because the
  same-direction rule only applies to focal changes.
- Across the cohort: 1 of 10 tumors has a loss (10%), 1 has CNLOH (10%),
  and 3 have gains (30%). The other 5 tumors are normal at GENE1.

## Cautions

- **Copy number is not adjusted for whole-genome doubling.** Some tumors
  have doubled their entire genome, so their baseline is 4 copies, not 2.
  This sheet uses 2 as the baseline for every tumor. In a doubled tumor, 4
  copies (labeled `TETRAPLOID`) count as a gain here, and 3 or 4 copies
  count as a gain even when FACETS describes them as a loss relative to
  the doubled genome (labels containing `LOSS`, such as `LOSS AFTER` or
  `CNLOH BEFORE & LOSS`, and `CNLOH BEFORE` / `CNLOH AFTER`). A gene can
  be on the sheet only because of one such call. The `wgd` column of the
  `facetsQC` sheet says which tumors FACETS considers genome-doubled.
  Check it and `cn_state_summary` before interpreting a gain.
- **The CNLOH column is broader than true CNLOH.** It counts every
  non-normal call with exactly 2 copies. Most are true CNLOH (FACETS
  labels `CNLOH` or `LOSS BEFORE`), but some are `DOUBLE LOSS AFTER`
  (a loss in a doubled genome, both parents' versions still present) or
  cases where FACETS could not tell (`DIPLOID or CNLOH`,
  `LOSS BEFORE or DOUBLE LOSS AFTER`).
- **Large high-level amplifications and deletions are left out
  upstream.** Before this sheet is built, FACETS removes calls it
  considers unlikely to target a single gene: `AMP` calls (5 or more
  copies) and `HOMDEL` calls (0 copies) on segments longer than 10 Mb or
  covering many genes. A tumor with, say, a whole-arm amplification at 6
  copies therefore does not appear in `samples_all` for genes on that arm
  and is not counted in `pct_amp`. Smaller gains (3 or 4 copies) and
  single-copy losses on large segments are kept. So `pct_amp` and
  `pct_loss` are complete for modest changes but undercount broad
  high-level ones.
- **"Focal" depends on segment size.** Whether a change counts as focal
  depends on where FACETS draws segment boundaries, which varies with data
  quality. The same gene can be focal in one tumor and part of a large
  change in another.
- **Small cohorts.** Each tumor is 100/N percent of the cohort; with 12
  tumors, one tumor is about 8%. In small cohorts, read the percentages as
  counts, not as population frequencies.
- **Normal and uncalled look the same.** A tumor missing from
  `samples_all` either has two normal copies of the gene, had a call that
  FACETS removed as described above, or had no sequenced variant positions
  in the gene. The sheet cannot tell these apart.
