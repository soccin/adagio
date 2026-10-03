# Variant Calling Pipeline

### Version 3.2.2

## Overview

Tumor/normal pairs were analyzed with the Tempo pipeline (Nextflow;
Di Tommaso 2017, Ewels 2020), run through our wrapper, adagio. The code,
including the exact Tempo version used, is at
[https://github.com/soccin/adagio/releases/tag/v3.2.2](https://github.com/soccin/adagio/releases/tag/v3.2.2).
Tempo was run from commit `a7ecd35` of
[https://github.com/soccin/tempo](https://github.com/soccin/tempo)
(branch `devs-iris`), a fork of
[https://github.com/mskcc/tempo](https://github.com/mskcc/tempo).
Reads were aligned to the GRCh37 reference with decoy sequences
(b37 + decoy).

## Methods

**Alignment.** Genome (WGS) BAMs were made with SMap; see
[https://github.com/soccin/SMap](https://github.com/soccin/SMap) for
details. Exome (WES) BAMs were made by Tempo, as follows.
Reads were aligned with BWA-MEM 0.7.17 (Li 2009) and
converted to BAM with samtools 1.9; fastp 0.19.7 was used for read QC
only, without trimming. With GATK 4.6.1.0 (McKenna 2010), lanes were
merged, sorted and duplicate-marked (MarkDuplicatesSpark), and base
qualities were recalibrated (BaseRecalibratorSpark, ApplyBQSRSpark) using
dbSNP 138, 1000 Genomes phase 1 indels and Mills indels as known sites.

**Somatic mutations.** SNVs and indels were called with GATK Mutect2
4.1.0.0 (Benjamin 2019) and with Strelka2 2.9.10 (Kim 2018) given
candidate indels from Manta 1.5.0 (Chen 2016); exome runs used the
`--exome` setting for Strelka2 and Manta. The union of the calls that
passed each caller's filters was annotated with RepeatMasker, the ENCODE blacklist, gnomAD r2.1.1
(non-cancer exomes for WES, genomes for WGS) and a panel of normals
(PoN), and converted to MAF with vcf2maf 1.6.17 and VEP 88 (McLaren 2016)
using MSK canonical isoforms. Mutations were annotated with OncoKB
(Chakravarty 2017) and cancer hotspots. A call was kept if it had tumor
depth >= 20, >= 3 alt reads and VAF >= 5% (2% at known hotspots), normal
depth >= 10 and <= 3 alt reads, gnomAD population maximum allele
frequency <= 1%, was seen in fewer than 10 PoN samples, and was not in a
repeat or blacklisted region. Tumor mutational burden (TMB, exomes only)
is the number of these mutations that are protein-changing (missense,
nonsense, nonstop, frameshift, in-frame indel, translation start, splice
site or splice region) and fall in the coding regions of the capture
target, divided by the size of those coding regions in Mb.

**Copy number.** Allele-specific copy number, purity and ploidy were
estimated with FACETS 0.5.14 (Shen 2016) through facets-suite 2.0.8, using
SNP pileups from snp-pileup (htstools 0.1.1). FACETS was run twice per
pair: a purity fit (cval 500 for WES, 5000 for WGS) and a high-sensitivity
fit (cval 100 for WES, 1000 for WGS). A sample is used for copy number
summaries if it passes FACETS QC or has `|dipLogR| < 0.5`.

**Structural variants (WGS only).** SVs were called with Delly, Manta,
SvABA and BRASS, merged, and annotated with iAnnotateSV.

**QC.** Tumor/normal concordance and contamination were checked with
Conpair 0.3.3 (Bergmann 2016). Alignment and coverage metrics came from
Alfred, Qualimap and GATK CollectHsMetrics (exomes), and were summarized
with MultiQC (Ewels 2016).

**Reports.** Custom R scripts in adagio build the delivered reports. The
SNV report keeps mutations that change the protein (a non-synonymous
`HGVSp_Short`) plus TERT promoter mutations, which are added back if
Tempo filtered them.

## References

Benjamin D, et al. Calling somatic SNVs and indels with Mutect2. bioRxiv
2019. doi:10.1101/861054

Bergmann EA, et al. Conpair: concordance and contamination estimator for
matched tumor-normal pairs. Bioinformatics 2016;32:3196-3198.
doi:10.1093/bioinformatics/btw389

Chakravarty D, et al. OncoKB: a precision oncology knowledge base. JCO
Precis Oncol 2017. doi:10.1200/PO.17.00011

Chen X, et al. Manta: rapid detection of structural variants and indels
for germline and cancer sequencing applications. Bioinformatics
2016;32:1220-1222. doi:10.1093/bioinformatics/btv710

Di Tommaso P, et al. Nextflow enables reproducible computational
workflows. Nat Biotechnol 2017;35:316-319. doi:10.1038/nbt.3820

Ewels P, et al. MultiQC: summarize analysis results for multiple tools
and samples in a single report. Bioinformatics 2016;32:3047-3048.
doi:10.1093/bioinformatics/btw354

Ewels PA, et al. The nf-core framework for community-curated
bioinformatics pipelines. Nat Biotechnol 2020;38:276-278.
doi:10.1038/s41587-020-0439-x

Kim S, et al. Strelka2: fast and accurate calling of germline and somatic
variants. Nat Methods 2018;15:591-594. doi:10.1038/s41592-018-0051-x

Li H, Durbin R. Fast and accurate short read alignment with
Burrows-Wheeler transform. Bioinformatics 2009;25:1754-1760.
doi:10.1093/bioinformatics/btp324

McKenna A, et al. The Genome Analysis Toolkit: a MapReduce framework for
analyzing next-generation DNA sequencing data. Genome Res
2010;20:1297-1303. doi:10.1101/gr.107524.110

McLaren W, et al. The Ensembl Variant Effect Predictor. Genome Biol
2016;17:122. doi:10.1186/s13059-016-0974-4

Shen R, Seshan VE. FACETS: allele-specific copy number and clonal
heterogeneity analysis tool for high-throughput DNA sequencing. Nucleic
Acids Res 2016;44:e131. doi:10.1093/nar/gkw520

Tempo. MSKCC CMO Computational Sciences.
[https://github.com/mskcc/tempo](https://github.com/mskcc/tempo)
