# TEMPO Structural Variant Output - Guide for Biologists

## What is this file?

The `tempoSVOutput.csv` file contains **structural variants (SVs)** detected in tumor samples compared to matched normal tissue. Structural variants are large DNA rearrangements including:

- **Deletions (DEL)**: Missing chunks of DNA
- **Duplications (DUP)**: Extra copies of DNA segments
- **Inversions (INV)**: DNA segments flipped backwards
- **Translocations (BND)**: DNA from different chromosomes joined together

## Quick Start: What columns should I look at first?

For a quick assessment, focus on these columns:

1. **TUMOR_ID** - Which sample
2. **TYPE** - What kind of rearrangement (BND translocations are often most interesting)
3. **fusion** - Is there a predicted gene fusion? In-frame fusions are functionally important
4. **gene1 & gene2** - Which genes are affected?
5. **NumCallersPass** - How many programs detected this? (2+ is good, 3-4 is very confident)
6. **t_svaba_VAF or t_delly_JuncVAF** - What percent of tumor cells have this? (higher = more clonal)
7. **CC_Tumour_Types** - Is this a known cancer gene?

## Understanding Evidence Strength

### How many detection programs found this variant?

- **NumCallers**: Total programs that found it (1-4)
- **NumCallersPass**: Programs where it passed quality filters (0-4)
- **Callers**: Actual program names (brass, delly, manta, svaba)

**Rule of thumb**: NumCallersPass >= 2 is reliable. NumCallersPass >= 3 is very confident.

### What is VAF and why does it matter?

**VAF = Variant Allele Fraction** = What percentage of cells have this mutation

Example columns:
- `t_svaba_VAF = 0.43` means 43% of tumor cells have this variant
- `n_svaba_VAF = 0.00` means 0% of normal cells have it (good - it's tumor-specific!)

**Key rules:**
- **Tumor VAF (t_)**: Higher is better (more tumor cells affected, more important)
  - 0.40-0.50: Present in most/all tumor cells (clonal, driver mutation)
  - 0.10-0.30: Present in subset of tumor cells (subclonal)
  - <0.10: Rare, may be technical artifact

- **Normal VAF (n_)**: Lower is better (want zero!)
  - 0.00-0.02: True somatic (tumor-only) mutation
  - >0.05: May be germline (inherited) variant
  - >0.40: Likely germline variant

### Read count evidence

Multiple programs count reads (DNA sequences) supporting the variant:

**From DELLY:**
- `delly_PE`: Paired-end reads (need 3+ for deletions, 5+ for translocations)
- `delly_SR`: Split reads (most precise evidence)
- `t_delly_DV`: Tumor variant pairs
- `n_delly_DV`: Normal variant pairs (want this to be 0)

**From MANTA:**
- `t_manta_SR`: Tumor split reads (format: "reference_count,variant_count")
  - Example: "97,19" = 97 normal reads, 19 variant reads
- `n_manta_SR`: Normal split reads (want variant count to be 0)

**From SvABA:**
- `t_svaba_AD`: Tumor allele depth (direct variant read count)
- `n_svaba_AD`: Normal allele depth (want 0)

**Rule of thumb**: Higher read counts in tumor + zero/low counts in normal = real somatic variant

## Understanding Gene Annotations

### Gene disruption columns

- **gene1 / gene2**: HUGO gene symbols affected
- **site1 / site2**: Where exactly in/near the gene the break occurred
  - "Exon of GENE" = breaks coding sequence (HIGH impact)
  - "Intron of GENE: Xbp after/before exon Y" = breaks between exons (moderate impact)
  - "IGR: Xkb before GENE" = intergenic region (may affect regulation)

### Fusion predictions

**fusion** column shows predicted protein fusions:
- "Protein Fusion: in frame {GENE1:GENE2}" = genes fused in correct reading frame
  - **In-frame fusions** preserve protein structure and often create functional oncoproteins
  - Example: BCR-ABL1 in leukemia, EML4-ALK in lung cancer

- "Protein Fusion: out of frame" = reading frame disrupted
  - Usually non-functional (but still disrupts normal gene function)

- Blank = no fusion predicted (may be simple gene disruption)

### Cancer Gene Census annotations (CC_ columns)

These link to the COSMIC Cancer Gene Census database:

- **CC_Tumour_Types**: Which cancers have somatic mutations in this gene
  - If filled in, this is a **known cancer gene**

- **CC_Mutation_Type**: How this gene acts in cancer
  - "oncogene" = activating mutations drive cancer (gain-of-function)
  - "TSG" = tumor suppressor gene, loss drives cancer (loss-of-function)
  - "fusion" = gene creates oncogenic fusions

- **CC_Translocation_Partner**: Known fusion partners
  - If your gene2 matches a known partner, this is a **recurrent cancer fusion**

### Database of Genomic Variants (DGv_ columns)

- **DGv_Name-DGv_VarType-site1/site2**: Known variants in healthy people

**Many entries here = may be benign/common variant**
**Blank = novel variant, more likely pathogenic**

## Identifying High-Confidence Cancer-Relevant Variants

### Priority 1: Known cancer gene fusions (in-frame)

Look for ALL of these:
- TYPE = "BND" (translocation)
- fusion contains "in frame"
- gene1 or gene2 is in CC_Tumour_Types (known cancer gene)
- NumCallersPass >= 2
- t_svaba_VAF or t_delly_JuncVAF >= 0.15 (present in 15%+ of tumor)
- n_svaba_VAF or n_delly_JuncVAF < 0.05 (absent from normal)
- DGv columns are blank or minimal (not a common benign variant)

**These are your top candidates for driver mutations**

### Priority 2: Disruption of tumor suppressor genes

Look for:
- CC_Mutation_Type contains "TSG" (tumor suppressor)
- site1 or site2 indicates "Exon" disruption
- NumCallersPass >= 2
- Tumor VAF >= 0.15, Normal VAF < 0.05

**Loss of tumor suppressors drives cancer**

### Priority 3: Novel fusions in cancer genes

Look for:
- fusion is "in frame" with genes not in CC_Translocation_Partner (novel fusion)
- But gene1 or gene2 is in CC_Tumour_Types (known to be involved in cancer)
- Strong evidence (NumCallersPass >= 3, high VAF, high read counts)

**May be new cancer-relevant fusions**

## Red Flags: Likely Artifacts or Germline Variants

Deprioritize variants with ANY of:
- NumCallersPass = 0 or 1 (only one caller, failed filters)
- Normal VAF > 0.40 (likely germline/inherited)
- Both repeat.site1 AND repeat.site2 filled in (breakpoints in repetitive DNA)
- Very low tumor VAF (<0.08) with low read counts (may be noise)
- Many entries in DGv columns (common benign variant)
- No gene annotation AND TYPE = DEL or DUP with SVLEN < 1000bp (small non-coding change)

## Example Interpretation Workflow

Let's analyze row 2 from the sample data:

```
TUMOR_ID: NK_KHYG1_CL_D
TYPE: DEL
fusion: Protein Fusion: in frame {CELA3B:CELA3A}
gene1: CELA3B, gene2: CELA3A
site1: Intron of CELA3B(+):87bp after exon 2
site2: Intron of CELA3A(+):82bp after exon 2
NumCallersPass: 2
Callers: manta,svaba,delly
t_delly_SpanVAF: 0.106 (10.6%)
n_delly_SpanVAF: 0 (0%)
t_svaba_VAF: 0.169 (16.9%)
n_svaba_VAF: 0 (0%)
t_manta_SR: 122,12 (12 variant split reads)
n_manta_SR: 1420,NA (0 variant reads in normal)
DGv_Name-DGv_VarType-site1: [many entries]
DGv_Name-DGv_VarType-site2: [many entries]
```

**Interpretation:**
1. **Evidence quality**: GOOD - detected by 3 callers, 2 passed filters
2. **Somatic status**: CONFIRMED - present in tumor (10-17% VAF), absent in normal (0%)
3. **Fusion**: In-frame fusion between CELA3B and CELA3A
4. **Read support**: GOOD - 12 split reads in tumor, 0 in normal
5. **Clinical relevance**: UNCERTAIN
   - These are elastase genes (digestive enzymes)
   - Not in Cancer Gene Census
   - Many DGv entries suggest this region has common variants
6. **Conclusion**: Real somatic deletion creating in-frame fusion, but uncertain clinical significance. CELA3B/CELA3A not known cancer genes. May be passenger mutation.

## Key Concepts Summary

### Somatic vs Germline
- **Somatic**: Mutation acquired in tumor (not inherited)
  - Present in tumor (high t_VAF), absent in normal (n_VAF ~0)
- **Germline**: Inherited mutation (in all cells)
  - Present in both tumor and normal (both VAF ~0.5 for heterozygous)

### Clonal vs Subclonal
- **Clonal**: Present in all/most tumor cells (VAF 0.4-0.5 after purity adjustment)
  - Usually early driver mutations
- **Subclonal**: Present in subset of cells (VAF 0.1-0.3)
  - Later mutations, tumor evolution

### Driver vs Passenger
- **Driver**: Mutation that promotes cancer growth
  - Usually affects known cancer genes
  - Often clonal (high VAF)
  - Functionally disruptive (in-frame fusions, tumor suppressor loss)
- **Passenger**: Random mutation with no functional effect
  - Novel genes not in cancer databases
  - May be subclonal
  - Not in functional regions

## Getting Help

Key resources:
- **Cancer Gene Census**: https://cancer.sanger.ac.uk/census
- **COSMIC Fusion Database**: https://cancer.sanger.ac.uk/cosmic/fusion
- **Database of Genomic Variants**: http://dgv.tcag.ca/

For questions about specific variants, consult with computational biologists or bioinformaticians who can:
- Look up genes in cancer databases
- Check if fusions are known in your cancer type
- Assess overall mutation burden and quality
- Integrate with other data (RNA-seq, copy number, etc.)

## Column Reference

For detailed column-by-column descriptions, see the file:
**tempoSVOutput_ColumnGuide.csv**

This contains all 56 columns with plain language explanations, typical values, and interpretation guidance.
