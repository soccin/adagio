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
  sits on a segment of fewer than 10 genes. Whole-arm and
  whole-chromosome changes are not counted here; they are in the FACETS
  report. Only autosomes are used. Samples whose FACETS fit is unreliable
  are left out of the CNV counts and show blank CNV cells.

## The sheets

**SampleSummary.** One row per tumor. The number of SV, SNV and CNV events,
how many of the SNVs are loss-of-function, the total mutation count
before filtering, and the FACETS estimates of purity, ploidy, fraction of
the genome altered, whole genome doubling and fit quality.

**GeneRanking.** One row per gene, ranked by how many tumors have any event
in it. A tumor counts once per gene even if it has several events there.
The next columns split that count by type: how many tumors have an SV,
an SNV, a loss-of-function SNV, a CNV, and whether the CNV is a gain, a
loss or copy-neutral LOH. The last column lists the tumors. Genes seen in
only one tumor are not shown.

A high rank is a reason to look, not a conclusion. Long genes collect
mutations by chance, and some regions are prone to artifacts in SV and
copy number calling. The counts have not been checked by eye.

**SVFreq_HV.** One row per pair of genes joined by a structural variant.
Columns:

- N: how many tumors have the pair.
- InFrame: how many of the calls are predicted to make an in-frame
  protein fusion.
- Dist_Mb: for pairs on the same chromosome, the distance between the
  two breakpoints in megabases. Blank for translocations.
- Bands: the chromosome bands of the two breakpoints, for example
  11q12.3-11q24.2.
- Pct: N as a fraction of the cohort.
- Samples: the tumors.

Pairs in two or more tumors are all shown. Pairs in a single tumor are
shown only when at least one call is an in-frame fusion.

**ColDescriptions.** The exact rule behind every column.

## Reading it

Start with GeneRanking for recurrent genes and SVFreq_HV for recurrent
or in-frame fusions. Use SampleSummary to see whether a few tumors
dominate the counts. For any gene or pair of interest, the full
supporting calls are in the SV, SNV and FACETS reports.
