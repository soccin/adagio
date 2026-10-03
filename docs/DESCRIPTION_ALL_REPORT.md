# The combined alteration report (All_Report01)

This workbook brings the three kinds of somatic change we call from the
whole-genome data into one place: structural variants (SV), point
mutations and small indels (SNV), and copy number changes (CNV). The
separate SV, SNV and FACETS reports still hold the full detail. This one
is for seeing which samples and which genes carry the most events.

## What counts as an event

- **SV**: a somatic structural variant call (deletion, duplication,
  inversion or translocation). Calls where both breakpoints are on the
  same chromosome and less than 1 Mb apart are left out everywhere in this
  workbook. Most of them are small deletions and duplications of
  uncertain meaning, and they would otherwise swamp the tables.
- **SNV**: a somatic mutation that changes the protein (missense,
  nonsense, frameshift, splice site, and so on). Silent and non-coding
  mutations are not counted. TERT promoter mutations are the one
  exception and are counted.
- **CNV**: a focal copy number change from FACETS. A call is focal when it
  sits on a segment 1 Mb or shorter, the same definition the FACETS
  report uses. Only calls with a FACETS filter of PASS or RESCUE are
  used, and only calls that are a gain, a loss or copy-neutral LOH
  (calls FACETS labels INDETERMINATE are not counted). Whole-arm and
  whole-chromosome changes are not counted
  here; they are in the FACETS report. Only autosomes are used. A sample
  contributes CNV events if it passed FACETS QC or its baseline
  log-ratio, `dipLogR`, is less than 0.5 from zero (`|dipLogR| < 0.5`).
  Other samples are left out of the CNV counts and show blank CNV cells.

## The sheets

**SampleSummary.** One row per tumor, with its matched normal. The number
of SV and SNV events, how many of the SNVs are loss-of-function, the
number of CNV events, the number of genes on the CNV segments, and the
total mutation count. The total is every mutation that passed Tempo's
filters, silent and non-coding ones included. Then come whole genome
doubling and the FACETS values: `facets_qc`, purity, ploidy, fraction of
the genome altered, `dipLogR`, and `cnv_included`, which says whether
the tumor contributes CNV events.

**GeneRanking.** One row per gene, ranked by how many tumors have any event
in it. A tumor counts once per gene even if it has several events there.
`Pct` is that count as a fraction of the cohort. The next columns split
the count by type: how many tumors have an SV,
an SNV, a loss-of-function SNV, a CNV, a CNV gain, a CNV loss, and a
copy-neutral LOH. A tumor can count in more than one of these columns. The last column lists the tumors. Genes seen in
only one tumor are not shown.

A high rank is a reason to look, not a conclusion. Long genes collect
mutations by chance, and some regions are prone to artifacts in SV and
copy number calling. The counts have not been checked by eye.

**SVFreq_HV.** One row per pair of genes joined by a structural variant.
Columns:

- genePair: the genes at the two breakpoints, in alphabetical order, for
  example GENEA::GENEB. A dot stands for a breakpoint that is not in a
  gene.
- N: how many tumors have the pair.
- InFrame: how many of the calls are predicted to make an in-frame
  protein fusion.
- Dist_Mb: for pairs on the same chromosome, the median distance between
  the two breakpoints over the pair's calls, in megabases. Blank for
  translocations.
- Bands: the chromosome bands of the two breakpoints, for example
  11q12.3-11q24.2. When the calls fall in different bands, each distinct
  band pair is listed, separated by semicolons.
- Pct: N as a fraction of the cohort.
- Samples: the tumors.

A pair is shown if it is in at least 5% of the tumors and either is in
two or more tumors or has at least one in-frame fusion call. In a cohort
of 20 or fewer tumors, one tumor is already 5% or more, so this reduces
to: pairs in two or more tumors, plus single-tumor pairs with an
in-frame fusion.

**ColDescriptions.** The exact rule behind every column.

## Reading it

Start with GeneRanking for recurrent genes and SVFreq_HV for recurrent
or in-frame fusions. Use SampleSummary to see whether a few tumors
dominate the counts. For any gene or pair of interest, the full
supporting calls are in the SV, SNV and FACETS reports.
