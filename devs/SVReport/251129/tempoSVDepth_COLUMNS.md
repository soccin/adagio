# tempoSVDepth.csv - Column Documentation

## Overview

This file contains structural variants with aggregated read depth metrics from TEMPO pipeline output. It includes original variant annotations (columns 1-20) plus computed depth aggregates (columns 21-42) that consolidate evidence across multiple SV callers (DELLY, MANTA, SvABA).

**Important**: Different callers count the same underlying reads, so read counts are **aggregated using MAX/MEDIAN** (not summed) to avoid overcounting.

---

## Column Groups

### 1. Variant Identifiers & Annotations (Columns 1-20)

| Column | Name | Description |
|--------|------|-------------|
| 1 | TUMOR_ID | Sample identifier |
| 2 | TYPE | Structural variant type: DEL, DUP, INV, BND (translocation) |
| 3 | fusion | Predicted gene fusion with frame status (in frame/out of frame) |
| 4-5 | gene1, gene2 | Genes affected by breakpoints |
| 6-7 | site1, site2 | Precise genomic locations (exon/intron/intergenic) |
| 8-13 | CHROM_A/B, START_A/B, END_A/B | Genomic coordinates for both breakpoints |
| 14 | STRANDS | Breakpoint orientation (++, --, +-, -+) |
| 15-16 | repeat.site1, repeat.site2 | Repetitive DNA elements at breakpoints |
| 17 | Callers | Comma-separated list of detection programs |
| 18 | NumCallers | Number of callers detecting variant (1-4) |
| 19 | NumCallersPass | Number of callers passing quality filters (0-4) |
| 20 | CC_Chr_Band | Cancer Gene Census chromosomal band |

### 2. Primary Depth Metrics (Columns 21-27) ⭐ USE THESE

| Column | Name | Description | Threshold |
|--------|------|-------------|-----------|
| 21 | manta_paired_reads | Paired-end read count from MANTA (MAPQ≥30) | ≥5 |
| 22 | manta_split_reads | Split read count from MANTA (MAPQ≥30) | ≥3 |
| 23 | max_paired_reads | Maximum paired-end count across all callers | ≥5 |
| 24 | max_split_reads | Maximum split read count across all callers | ≥3 |
| 25 | median_paired_reads | Median paired-end count across callers | ≥5 |
| 26 | median_split_reads | Median split read count across callers | ≥3 |
| 27 | total_max_reads | Sum of max_paired + max_split | ≥10 |

**Recommendation**: Use columns 21-22 (MANTA only) for highest quality, or 23-24 (MAX) for most sensitive detection.

### 3. Quality Indicators (Columns 28-35)

| Column | Name | Description |
|--------|------|-------------|
| 28 | has_paired_evidence | TRUE if paired-end reads detected |
| 29 | has_split_evidence | TRUE if split reads detected |
| 30 | multi_evidence_type | TRUE if both PE and SR present (strongest evidence) |
| 31 | callers_with_3plus_split | Number of callers seeing ≥3 split reads (0-3) |
| 32 | callers_with_5plus_paired | Number of callers seeing ≥5 paired reads (0-3) |
| 33 | meets_split_threshold | TRUE if max_split_reads ≥ 3 |
| 34 | meets_paired_threshold | TRUE if max_paired_reads ≥ 5 |
| 35 | high_quality_evidence | TRUE if all quality criteria met ⭐ PRIMARY FILTER |

**high_quality_evidence** = TRUE requires: max_split ≥3, max_paired ≥5, both evidence types, NumCallersPass ≥2

### 4. Individual Caller Counts (Columns 36-42) - Reference Only

| Column | Name | Caller | Type | Source Field |
|--------|------|--------|------|--------------|
| 36 | delly_paired | DELLY | Paired-end | t_delly_DV |
| 37 | delly_split | DELLY | Split reads | t_delly_RV |
| 38 | manta_paired | MANTA | Paired-end | t_manta_PR (ALT extracted) |
| 39 | manta_split | MANTA | Split reads | t_manta_SR (ALT extracted) |
| 40 | svaba_paired | SvABA | Discordant | t_svaba_DR |
| 41 | svaba_split | SvABA | Spanning | t_svaba_SR |
| 42 | svaba_total | SvABA | Total variant | t_svaba_AD |

---

## Quick Usage Guide

### For Biologists

**Filter to high-confidence variants:**
- Open in Excel, filter column 35 (`high_quality_evidence`) to TRUE
- This gives you 379 variants (82.9%) meeting all quality thresholds

**Check evidence strength:**
- Column 24 (`max_split_reads`): Higher = more reads spanning exact breakpoint
- Column 30 (`multi_evidence_type`): TRUE = both paired-end and split read support

**Prioritize by clinical relevance:**
1. Column 3 (`fusion`) contains "in frame" → functional fusion protein
2. Columns 4-5 (`gene1`, `gene2`) are known cancer genes
3. Column 35 (`high_quality_evidence`) = TRUE

### For Computational Analysts

**R filtering example:**
```r
library(tidyverse)
df <- read_csv("tempoSVDepth.csv")

# High quality variants
hq <- df %>% filter(high_quality_evidence == TRUE)

# Custom stringent filter
stringent <- df %>%
  filter(max_split_reads >= 5,
         max_paired_reads >= 10,
         NumCallersPass >= 3)
```

**Python example:**
```python
import pandas as pd
df = pd.read_csv("tempoSVDepth.csv")

# High quality filter
hq = df[df['high_quality_evidence'] == True]

# Check caller agreement
consensus = df[(df['NumCallersPass'] >= 2) &
               (df['multi_evidence_type'] == True)]
```

---

## Key Concepts

### Read Types

- **Paired-End (PE)**: Read pairs with unexpected orientation/distance → suggests SV but imprecise
- **Split Reads (SR)**: Individual reads split-aligned across junction → pinpoints exact breakpoint (higher quality)

### Aggregation Methods

- **MANTA only** (cols 21-22): Single caller, highest quality (MAPQ≥30), simplest
- **MAX** (cols 23-24): Most sensitive across all callers
- **MEDIAN** (cols 25-26): Central tendency, robust to outliers
- **DO NOT SUM**: Callers analyze same BAM file and count same reads

### Quality Thresholds

| Evidence Level | Split Reads | Paired Reads | Callers Pass | Classification |
|----------------|-------------|--------------|--------------|----------------|
| Excellent | ≥10 | ≥20 | ≥3 | Very high confidence |
| Good | ≥5 | ≥10 | ≥2 | High confidence |
| Moderate | ≥3 | ≥5 | ≥2 | Standard threshold |
| Weak | <3 | <5 | <2 | Likely artifact |

---

## Dataset Statistics

**457 structural variants analyzed:**
- 379 (82.9%) pass high_quality_evidence criteria
- 385 (84.2%) have multiple evidence types
- 386 (84.5%) meet split read threshold
- 450 (98.5%) meet paired read threshold

**Median read counts:**
- Median max_split_reads: 30
- Median max_paired_reads: 26

---

## Files in Directory

- `tempoSVOutput.csv` - Original TEMPO output (56 columns, all callers)
- `tempoSVDepth.csv` - This file (42 columns, aggregated depth)
- `compute_depth_aggregates.R` - R script that generated this file
- `tempoSVDepth_COLUMNS.md` - This documentation
- `AGGREGATING_READ_COUNTS.md` - Detailed technical explanation

---

## Contact & Questions

**For questions about:**
- Column definitions → See this file
- Why we don't sum read counts → See `AGGREGATING_READ_COUNTS.md`
- Original TEMPO output columns → See `tempoSVOutput_ColumnGuide.csv`
- General SV interpretation → See `GUIDE_FOR_BIOLOGISTS.md`
