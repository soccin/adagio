# Read Depth Fields in TEMPO SV Output (Actual File)

## Overview

**27 out of 56 columns** in `tempoSVOutput.csv` contain depth/read count information:
- **7 VAF columns** (pre-calculated percentages)
- **20 raw read count columns** (actual number of reads)

## What is "Depth"?

**Depth = Read Count** = How many times the DNA sequencer read that region

Higher counts = More reliable evidence

---

## 1. VAF COLUMNS (7 total)

**VAF = Variant Allele Fraction** = What % of cells have the variant

### Tumor VAF (higher is better)

| Excel | Column Name | Caller | What It Measures |
|-------|-------------|--------|------------------|
| **U** | t_delly_SpanVAF | DELLY | % tumor cells with variant (spanning reads) |
| **V** | t_delly_JuncVAF | DELLY | % tumor cells with variant (junction reads - more precise) |
| **Y** | t_svaba_VAF | SvABA | % tumor cells with variant |
| **AA** | t_manta_JuncVAF | MANTA | % tumor cells with variant (junction reads) |

**Good values**: 0.15-0.50 (variant in 15-50% of tumor cells)

### Normal VAF (lower is better - want 0)

| Excel | Column Name | Caller | What It Measures |
|-------|-------------|--------|------------------|
| **W** | n_delly_SpanVAF | DELLY | % normal cells with variant (spanning) |
| **X** | n_delly_JuncVAF | DELLY | % normal cells with variant (junction) |
| **Z** | n_svaba_VAF | SvABA | % normal cells with variant |

**Good values**: 0.00-0.02 (absent from normal = truly somatic)

---

## 2. RAW READ COUNT COLUMNS (20 total)

### DELLY Counts (10 columns)

**Simple totals (no sample separation):**

| Excel | Column Name | What It Counts | Good Values |
|-------|-------------|----------------|-------------|
| **AB** | delly_PE | Paired-end reads supporting variant | ≥5 (BND) or ≥3 (DEL/DUP/INV) |
| **AC** | delly_SR | Split reads supporting variant (most precise) | ≥3 |

**Tumor counts:**

| Excel | Column Name | Type | What It Counts | Good Values |
|-------|-------------|------|----------------|-------------|
| **AL** | t_delly_DR | Paired-end | Reference (normal) allele reads | N/A |
| **AM** | t_delly_DV | Paired-end | Variant allele reads | ≥5 |
| **AN** | t_delly_RR | Junction/split | Reference junction reads | N/A |
| **AO** | t_delly_RV | Junction/split | Variant junction reads | ≥3 |

**Normal counts (want variant counts = 0):**

| Excel | Column Name | Type | What It Counts | Good Values |
|-------|-------------|------|----------------|-------------|
| **AQ** | n_delly_DR | Paired-end | Reference reads | N/A |
| **AR** | n_delly_DV | Paired-end | Variant reads | 0 |
| **AS** | n_delly_RR | Junction/split | Reference junction reads | N/A |
| **AT** | n_delly_RV | Junction/split | Variant junction reads | 0 |

### MANTA Counts (4 columns)

**Format**: "REF_count,ALT_count" (example: "106,6" = 106 reference, 6 variant)

**Tumor:**

| Excel | Column Name | Type | Format | Look For |
|-------|-------------|------|--------|----------|
| **AD** | t_manta_PR | Paired reads | REF,ALT | ALT ≥5 |
| **AE** | t_manta_SR | Split reads | REF,ALT | ALT ≥3 (highest quality) |

**Normal (want ALT=0):**

| Excel | Column Name | Type | Format | Look For |
|-------|-------------|------|--------|----------|
| **AH** | n_manta_PR | Paired reads | REF,ALT | ALT = 0 |
| **AI** | n_manta_SR | Split reads | REF,ALT | ALT = 0 |

### SvABA Counts (6 columns)

**Tumor:**

| Excel | Column Name | What It Counts | Good Values |
|-------|-------------|----------------|-------------|
| **AF** | t_svaba_AD | Reads with variant allele | ≥5 |
| **AG** | t_svaba_SR | Spanning reads supporting variant | ≥3 |
| **AP** | t_svaba_DR | Discordant read pairs | ≥3 |

**Normal (want all = 0):**

| Excel | Column Name | What It Counts | Good Values |
|-------|-------------|----------------|-------------|
| **AJ** | n_svaba_AD | Reads with variant allele | 0 |
| **AK** | n_svaba_SR | Spanning reads | 0 |
| **AU** | n_svaba_DR | Discordant read pairs | 0 |

---

## Quick Reference for Biologists

### Easiest columns to check (3 columns):

1. **Column Y (t_svaba_VAF)** - Is variant in tumor? (want 0.15-0.50)
2. **Column Z (n_svaba_VAF)** - Is it absent from normal? (want 0.00)
3. **Column AE (t_manta_SR)** - Split read evidence in tumor (look at 2nd number, want ≥3)

### Strong evidence pattern:

**Tumor high:**
- Column AM (t_delly_DV) ≥5
- Column AO (t_delly_RV) ≥3
- Column AF (t_svaba_AD) ≥5
- Column AE (t_manta_SR) shows ALT ≥3

**Normal zero/low:**
- Column AR (n_delly_DV) = 0
- Column AT (n_delly_RV) = 0
- Column AJ (n_svaba_AD) = 0
- Column AI (n_manta_SR) shows ALT = 0

### Weak/artifact pattern:

- Tumor VAF <0.08 (columns U,V,Y,AA)
- Normal VAF >0.05 (columns W,X,Z)
- Low tumor counts: Column AF <5, Column AO <3
- Counts in normal: Column AR >0, Column AJ >0

---

## Understanding Different Read Types

### Paired-End Reads (PE)
- Two ends of same DNA fragment point wrong direction or distance
- Indicates DNA rearrangement
- Examples: delly_PE (AB), t_manta_PR (AD), t_delly_DV (AM)

### Split/Junction Reads (SR)
- Single read spans the exact breakpoint
- **Most precise evidence** - pinpoints exact break location
- Examples: delly_SR (AC), t_manta_SR (AE), t_delly_RV (AO)

### Discordant Reads (DR)
- Read pairs with unexpected orientation/distance
- Similar to paired-end
- Examples: t_svaba_DR (AP), n_svaba_DR (AU)

### Spanning Reads
- Reads that cross the breakpoint region
- Examples: t_svaba_SR (AG), n_svaba_SR (AK)

---

## Example Interpretation

**Variant from row 5 of sample data:**

| Column | Value | Interpretation |
|--------|-------|----------------|
| V (t_delly_JuncVAF) | 0.066 | 6.6% of tumor cells (LOW - subclonal) |
| X (n_delly_JuncVAF) | 0.000 | 0% of normal cells (GOOD - somatic) |
| Y (t_svaba_VAF) | 0.167 | 16.7% of tumor cells (MODERATE) |
| Z (n_svaba_VAF) | 0.000 | 0% of normal (GOOD - somatic) |
| AB (delly_PE) | 8 | 8 paired-end reads (GOOD - ≥5) |
| AC (delly_SR) | 3 | 3 split reads (GOOD - ≥3) |
| AE (t_manta_SR) | 176,4 | 4 variant split reads (MODERATE) |
| AI (n_manta_SR) | 1350,NA | 0 variant reads in normal (GOOD) |
| AF (t_svaba_AD) | 10 | 10 variant reads in tumor (GOOD) |
| AJ (n_svaba_AD) | 0 | 0 variant reads in normal (GOOD) |

**Conclusion**: Real somatic variant (present in tumor, absent in normal) with moderate VAF (7-17%). Multiple read types support it. Present in subset of tumor cells (subclonal).

---

## Key Takeaways

1. **VAF (columns U-Z, AA)** - Easiest to interpret, shows % of cells
2. **Check BOTH tumor (want high) AND normal (want 0)** - Proves it's somatic
3. **Split reads (SR) are most reliable** - They span exact breakpoint
4. **Multiple evidence types = stronger call** - PE + SR better than PE alone
5. **Focus on columns Y,Z,AB,AE,AF for quick assessment**
