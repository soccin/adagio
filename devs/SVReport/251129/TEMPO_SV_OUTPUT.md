# TEMPO Structural Variant Output Column Descriptions

## Overview

**TEMPO Pipeline**: A computational pipeline for processing paired whole-genome/exome sequencing of human cancer samples with matched normals. It integrates multiple structural variant callers to increase sensitivity and specificity through consensus calling.

**The Four SV Callers**:
1. **BRASS** (Sanger): Assembly-based breakpoint detection
2. **DELLY**: Paired-end and split-read analysis
3. **MANTA** (Illumina): Optimized for somatic tumor/normal pairs
4. **SvABA**: Local assembly-based detection

---

## DETAILED COLUMN DESCRIPTIONS

### BRASS Fields (Breakpoints via Assembly)

**brass_BAS** (Assembly Score, 0-100)
- Measures the "niceness" of the Velvet de Bruijn assembly graph
- Score of 100 = perfect quintet pattern (5 vertices)
- Higher scores indicate cleaner, more confident breakpoint assemblies
- Low scores suggest complex/ambiguous breakpoint structures

**brass_SVCLASS** (deletion, inversion, tandem-duplication, translocation)
- Basic structural variant classification based on orientation and distance

**brass_MATEID**
- Links paired breakends in translocations/inversions
- Critical for reconstructing complete rearrangement events

**brass_BKDIST**
- Distance in base pairs between breakpoints
- -1 for interchromosomal events
- Helps distinguish local rearrangements from large-scale events

**brass_FFV** (Fusion Flag Value)
- Indicates potential gene fusion events
- Reports the best/highest confidence fusion annotation

**brass_OCC** (Occurrence Count)
- Number of times this exact breakpoint appears in the dataset
- High values may indicate technical artifacts or germline variants
- Useful for filtering recurrent false positives

**Annotation Fields (brass_SID through brass_RGNC)**
- **brass_SID**: Gene database identifier or "unknown"
- **brass_GENE**: HUGO gene symbol - essential for identifying clinically relevant gene disruptions
- **brass_TID**: Specific transcript affected
- **brass_AS**: Strand orientation (+/-)
- **brass_EPH/brass_PH**: Phase information for coding sequences (0, 1, or 2) - critical for predicting protein impact
- **brass_RGN**: Genomic region (exon, intron, UTR, intergenic, etc.)
- **brass_RGNNO/brass_RGNC**: Which exon/intron out of total count (e.g., "exon 5 of 12")

**brass_TSRDS** ⭐ READ DEPTH
- **T**umor **S**panning **R**ea**DS**: Reads spanning across (but not supporting) the rearrangement
- Provides local coverage context

**brass_TRDS** ⭐ READ DEPTH
- **T**umor **R**ea**DS**: Reads directly supporting/contributing to the rearrangement
- Key evidence metric for variant calling

---

### DELLY Fields (Paired-End/Split-Read Caller)

**delly_CIEND / delly_CIPOS** (Confidence Intervals)
- Uncertainty ranges around END and POS coordinates
- Format: start_offset,end_offset (e.g., -10,10)
- Smaller intervals = more precise breakpoint localization

**delly_PE** ⭐ READ DEPTH
- **Paired-End support**: Number of discordant read pairs supporting the SV
- Primary evidence metric
- Filtering threshold: PE ≥3 for DEL/DUP/INV, PE ≥5 for translocations

**delly_MAPQ** ⭐ MAPPING QUALITY (related to depth quality)
- **Median mapping quality** of supporting paired-end reads
- Range: 0-60; higher = better
- Filtering threshold: MAPQ ≥20 required for PASS
- Low MAPQ suggests repetitive regions or ambiguous alignments

**delly_CT** (Connection Type)
- Paired-end signature pattern: 3to3, 5to5, 3to5, 5to3
- Defines breakpoint orientation and SV type

**delly_IMPRECISE**
- Flag indicating breakpoint cannot be resolved to single-base resolution
- Common in repeat-rich regions

**delly_SVMETHOD**
- "EMBL.DELLYv0.X.X" - version tracking

**delly_RDRATIO** ⭐ READ DEPTH
- **Read-depth ratio** of tumor vs. normal
- Expected values: ~0.5 for deletions, ~1.5-2.0 for duplications
- Provides copy number context for SVs

**delly_SOMATIC**
- Boolean flag: variant called as somatic (tumor-specific)

**delly_AC / delly_AN**
- Allele count and total alleles across samples
- Genotyping information

**FORMAT Fields**:

**delly_GQ** - Genotype Quality score

**delly_FT** - Per-sample filter status (PASS/LowQual)

**delly_RC / delly_RCL / delly_RCR** ⭐ READ DEPTH
- **RC**: Raw high-quality read counts at the SV
- **RCL**: Read counts in **L**eft control region (flanking)
- **RCR**: Read counts in **R**ight control region (flanking)
- Used together to detect copy number changes

**delly_CN** ⭐ READ DEPTH
- **Copy Number** estimate based on read depth
- Autosomal sites only
- Integrates RC, RCL, RCR ratios

**delly_DR / delly_DV** ⭐ READ DEPTH
- **DR**: High-quality **R**eference pairs (normal/expected orientation)
- **DV**: High-quality **V**ariant pairs (supporting SV)
- Ratio DV/(DR+DV) approximates variant allele frequency

**delly_RR / delly_RV** ⭐ READ DEPTH
- **RR**: **R**eference junction **R**eads (split reads supporting reference)
- **RV**: **V**ariant junction reads (split reads supporting SV)
- Provides independent validation from split-read evidence

---

### MANTA Fields (Illumina's SV Caller)

**manta_IMPRECISE / manta_CIPOS / manta_CIEND**
- Same concepts as DELLY (confidence intervals and precision flags)

**manta_MATEID**
- Links breakend pairs for BND (translocation) records

**manta_SVINSLEN / manta_SVINSSEQ**
- **Length** and **sequence** of inserted bases at breakpoint
- Critical for complex rearrangements with novel sequence insertions
- Empty if no insertion detected

**manta_BND_DEPTH** ⭐ READ DEPTH
- Read depth at the **local** translocation breakend
- Provides coverage context at primary breakpoint

**manta_MATE_BND_DEPTH** ⭐ READ DEPTH
- Read depth at the **remote** mate breakend
- Allows comparison of coverage at both sides of translocation
- Asymmetric depths may indicate copy number changes

**manta_SOMATIC**
- Boolean somatic classification flag

**manta_SOMATICSCORE** ⭐ QUALITY SCORE
- Phred-scaled somatic variant quality score
- Higher scores = greater confidence in somatic classification
- Used for filtering low-confidence somatic calls

**FORMAT Fields**:

**manta_PR** ⭐ READ DEPTH
- **P**aired-end **R**eads: Format "REF_count,ALT_count"
- Counts spanning read pairs with MAPQ ≥30 (high quality only)
- Example: "10,5" = 10 reference pairs, 5 variant pairs

**manta_SR** ⭐ READ DEPTH
- **S**plit **R**eads: Format "REF_count,ALT_count"
- Counts split-reads with MAPQ ≥30
- Provides independent orthogonal evidence to PR
- High SR/PR ratio suggests precise breakpoints

---

### SvABA Fields (Assembly-Based Caller)

**svaba_DISC_MAPQ** ⭐ MAPPING QUALITY
- Mean mapping quality of discordant reads at this location
- Indicates reliability of discordant evidence

**svaba_NUMPARTS**
- Number of assembly parts/fragments used
- Higher values may indicate complex rearrangements

**svaba_MATEID**
- Links mate breakends

**svaba_MAPQ** ⭐ MAPPING QUALITY
- BWA-MEM mapping quality of the assembled contig fragment
- -1 if variant detected by discordant reads only (no assembly)
- High MAPQ = confident contig alignment

**svaba_SCTG**
- **Contig identifier** from SvABA assembly
- Format: "contig_XXXX"
- Can be used to extract detailed alignment info from alignment.txt.gz files
- Links VCF variant to specific assembled sequence

**svaba_NM / svaba_MATENM**
- **Number of Mismatches** in contig alignment to reference
- NM: this breakend fragment
- MATENM: mate breakend fragment
- Lower values = better assembly quality

**svaba_SPAN**
- Distance between breakpoints in base pairs
- -1 for interchromosomal
- Similar to brass_BKDIST

**svaba_INSERTION**
- Inserted sequence at breakpoint
- May represent templated insertions or complex rearrangements

**svaba_IMPRECISE**
- Precision flag (same as other callers)

**svaba_EVDNC** (Evidence Type)
- "ASSMB" = assembly-based detection
- Indicates detection method (vs. discordant-only)

**FORMAT Fields**:

**svaba_LR** ⭐ QUALITY SCORE
- **Log-odds Ratio**: REF vs. AF=0.5
- Used for somatic/germline classification
- Positive = favors reference, negative = favors heterozygous/somatic

**svaba_DR / svaba_SR** ⭐ READ DEPTH
- **DR**: **D**iscordant **R**ead support for variant
- **SR**: **S**panning **R**ead support for variant
- Combined evidence from different read types

**svaba_PL**
- Phred-scaled genotype likelihoods (standard VCF)

**svaba_GQ**
- Genotype Quality (currently always 0 - not implemented)

**svaba_LO** ⭐ QUALITY SCORE
- **Log-Odds**: variant is real vs. artifact
- Incorporates local repeat structure (longer repeats = higher artifact likelihood)
- Primary quality metric for filtering

**svaba_DP** ⭐ READ DEPTH
- **Depth of coverage**: Total reads covering the site
- Standard VCF depth metric

**svaba_AD** ⭐ READ DEPTH
- **Allele Depth**: Reads supporting the variant allele
- AD/DP ratio approximates variant allele frequency

---

### Consensus/Merged Fields

**Callers**
- Comma-separated list of which callers detected this variant
- More callers = higher confidence
- Example: "brass,delly,manta"

**NumCallers**
- Integer count of supporting callers (1-4)
- Multi-caller support reduces false positives

**NumCallersPass**
- Count of callers where variant passed filters (not just detected)
- More stringent than NumCallers

**CHR2 / END / SVTYPE / SVLEN / STRANDS**
- Standard VCF SV fields
- **CHR2**: Second chromosome for translocations
- **END**: End coordinate (or second breakpoint position)
- **SVTYPE**: DEL, DUP, INV, BND (breakend/translocation)
- **SVLEN**: Length of variant (negative for deletions)
- **STRANDS**: Orientation signature (++, --, +-, -+)

**delly_filters**
- Filter annotations from DELLY (LowQual, PASS, etc.)

---

## READ DEPTH FIELDS SUMMARY

### Direct Read Count Fields:
1. **brass_TSRDS** - Tumor spanning reads
2. **brass_TRDS** - Tumor supporting reads
3. **delly_PE** - Paired-end support count
4. **delly_RC/RCL/RCR** - Read counts (SV region, left control, right control)
5. **delly_CN** - Copy number from read depth
6. **delly_DR/DV** - Reference/variant paired-end reads
7. **delly_RR/RV** - Reference/variant junction reads
8. **manta_BND_DEPTH** - Depth at local breakend
9. **manta_MATE_BND_DEPTH** - Depth at remote breakend
10. **manta_PR** - Paired-read counts (REF,ALT)
11. **manta_SR** - Split-read counts (REF,ALT)
12. **svaba_DR** - Discordant read support
13. **svaba_SR** - Spanning read support
14. **svaba_DP** - Total depth of coverage
15. **svaba_AD** - Variant allele depth

### Read Quality/Mapping Fields (depth-related):
16. **delly_MAPQ** - Median mapping quality
17. **svaba_DISC_MAPQ** - Discordant read mapping quality
18. **svaba_MAPQ** - Contig mapping quality
19. **delly_RDRATIO** - Tumor/normal read-depth ratio

---

## PRACTICAL INTERPRETATION GUIDANCE

### High-Confidence Somatic SVs Should Have:
- NumCallersPass ≥ 2
- delly_PE ≥ 5 (for translocations) or ≥ 3 (other SVs)
- delly_MAPQ ≥ 20
- manta_SOMATICSCORE > 30
- svaba_LO > 5 (log-odds favoring real variant)
- Adequate depth: manta_BND_DEPTH ≥ 10, svaba_DP ≥ 10

### Red Flags for Artifacts:
- NumCallers = 1 and caller is DELLY or SvABA alone
- brass_OCC > 5 (recurrent in dataset)
- High svaba_NM (many mismatches in assembly)
- delly_IMPRECISE flag with low PE support
- Asymmetric manta_BND_DEPTH vs MATE_BND_DEPTH without CN changes

### Functional Impact Prioritization:
- brass_GENE = known cancer gene
- brass_RGN = "exon" (coding impact)
- brass_FFV present (potential fusion)
- SVTYPE = translocation with brass_GENE annotations on both sides

---

## Sources:
- [BRASS GitHub Repository](https://github.com/cancerit/BRASS)
- [BRASS BEDPE Format Documentation](https://github.com/cancerit/BRASS/wiki/BEDPE)
- [DELLY GitHub Repository](https://github.com/dellytools/delly)
- [DELLY VCF Example](https://github.com/VCCRI/SVPV/blob/master/example/delly.vcf)
- [MANTA GitHub Repository](https://github.com/Illumina/manta)
- [MANTA User Guide](https://github.com/Illumina/manta/blob/master/docs/userGuide/README.md)
- [SvABA GitHub Repository](https://github.com/walaj/svaba)
- [SvABA Publication - PMC](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5880247/)
- [TEMPO Pipeline Documentation](https://deploy-preview-983--cmotempo.netlify.app/)
