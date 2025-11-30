# tempoSVDepth.csv - Documentation

## Overview

This file contains aggregate depth metrics computed from `tempoSVOutput.csv`. It includes:
- **Columns 1-20**: Original identifier and annotation columns (A-T)
- **Columns 21-42**: Computed aggregate depth metrics

## How the File Was Created

```bash
Rscript compute_depth_aggregates.R
```

**Input**: `tempoSVOutput.csv` (457 variants)
**Output**: `tempoSVDepth.csv` (457 rows × 42 columns)

## Key Finding

Different callers (DELLY, MANTA, SvABA) count the **same physical reads**, so we **cannot sum** them. Instead, this analysis uses:
- **MAX**: Most sensitive detection
- **MEDIAN**: Central tendency
- **MANTA alone**: Highest quality (MAPQ≥30 filtering)

## Column Descriptions

### Original Columns (1-20, A-T)

| Col | Name | Description |
|-----|------|-------------|
| 1 | TUMOR_ID | Sample identifier |
| 2 | TYPE | SV type (DEL, DUP, INV, BND) |
| 3 | fusion | Predicted gene fusion |
| 4-5 | gene1, gene2 | Affected genes |
| 6-7 | site1, site2 | Breakpoint locations |
| 8-13 | CHROM_A, START_A, END_A, CHROM_B, START_B, END_B | Genomic coordinates |
| 14 | STRANDS | Breakpoint orientation |
| 15-16 | repeat.site1, repeat.site2 | Repetitive elements |
| 17 | Callers | Which programs detected variant |
| 18 | NumCallers | Count of detecting callers (1-4) |
| 19 | NumCallersPass | Count passing filters (0-4) |
| 20 | CC_Chr_Band | Cancer Census chromosomal band |

### Recommended Aggregate Metrics (21-27)

**Use these for analysis!**

| Col | Name | Description | Good Values |
|-----|------|-------------|-------------|
| **21** | **manta_paired_reads** | MANTA paired-end ALT count | ≥5 |
| **22** | **manta_split_reads** | MANTA split-read ALT count | ≥3 |
| **23** | **max_paired_reads** | Maximum paired reads across callers | ≥5 |
| **24** | **max_split_reads** | Maximum split reads across callers | ≥3 |
| 25 | median_paired_reads | Median paired reads across callers | ≥5 |
| 26 | median_split_reads | Median split reads across callers | ≥3 |
| 27 | total_max_reads | Sum of max_paired + max_split | ≥10 |

**Simplest approach**: Use columns 21-22 (MANTA alone) - cleanest format, highest quality

**Most sensitive**: Use columns 23-24 (MAX across callers) - catches all detections

### Quality Indicators (28-35)

| Col | Name | Description | Interpretation |
|-----|------|-------------|----------------|
| 28 | has_paired_evidence | Any paired-end reads? | TRUE = has PE evidence |
| 29 | has_split_evidence | Any split reads? | TRUE = has SR evidence |
| **30** | **multi_evidence_type** | Both PE and SR present? | **TRUE = strongest evidence** |
| 31 | callers_with_3plus_split | How many callers see ≥3 split reads | 0-3 (higher = more agreement) |
| 32 | callers_with_5plus_paired | How many callers see ≥5 paired reads | 0-3 (higher = more agreement) |
| 33 | meets_split_threshold | max_split_reads ≥ 3? | TRUE = passes threshold |
| 34 | meets_paired_threshold | max_paired_reads ≥ 5? | TRUE = passes threshold |
| **35** | **high_quality_evidence** | Passes all quality criteria? | **TRUE = high confidence** |

**high_quality_evidence** = TRUE when ALL of:
- max_split_reads ≥ 3
- max_paired_reads ≥ 5
- Both PE and SR evidence present
- NumCallersPass ≥ 2

### Individual Caller Counts (36-42)

Reference columns showing counts from each caller:

| Col | Name | Caller | Type | Description |
|-----|------|--------|------|-------------|
| 36 | delly_paired | DELLY | Paired-end | t_delly_DV |
| 37 | delly_split | DELLY | Split reads | t_delly_RV |
| 38 | manta_paired | MANTA | Paired-end | t_manta_PR ALT count |
| 39 | manta_split | MANTA | Split reads | t_manta_SR ALT count |
| 40 | svaba_paired | SvABA | Discordant | t_svaba_DR |
| 41 | svaba_split | SvABA | Spanning | t_svaba_SR |
| 42 | svaba_total | SvABA | Total | t_svaba_AD (DR+SR) |

## Data Summary

From the 457 variants analyzed:

- **82.1%** have MANTA split reads
- **84.5%** meet split read threshold (≥3)
- **98.5%** meet paired read threshold (≥5)
- **84.2%** have multi-evidence type (both PE and SR)
- **82.9%** classified as high quality evidence

**Median counts:**
- Median max_split_reads: **30**
- Median max_paired_reads: **26**

## Recommended Analysis Workflow

### Step 1: Filter to High-Quality Variants

```r
library(tidyverse)

df <- read_csv("tempoSVDepth.csv")

# Filter to high quality
high_qual <- df %>%
  filter(high_quality_evidence == TRUE)

# Or custom thresholds
stringent <- df %>%
  filter(
    max_split_reads >= 5,
    max_paired_reads >= 10,
    multi_evidence_type == TRUE,
    NumCallersPass >= 3
  )
```

### Step 2: Prioritize by Evidence Strength

```r
prioritized <- df %>%
  mutate(
    evidence_score = max_split_reads + max_paired_reads,
    evidence_tier = case_when(
      high_quality_evidence & evidence_score >= 50 ~ "Tier1_Excellent",
      high_quality_evidence ~ "Tier2_Good",
      meets_split_threshold | meets_paired_threshold ~ "Tier3_Moderate",
      TRUE ~ "Tier4_Weak"
    )
  ) %>%
  arrange(desc(evidence_score))
```

### Step 3: Analyze Caller Agreement

```r
# Variants with strong caller agreement
consensus <- df %>%
  filter(
    NumCallersPass >= 3,
    callers_with_3plus_split >= 2,
    callers_with_5plus_paired >= 2
  )
```

### Step 4: Compare Aggregation Methods

```r
# See difference between MAX and MEDIAN
df %>%
  mutate(
    split_diff = max_split_reads - median_split_reads,
    paired_diff = max_paired_reads - median_paired_reads
  ) %>%
  select(TUMOR_ID, TYPE, gene1, gene2,
         max_split_reads, median_split_reads, split_diff,
         NumCallersPass)
```

Large differences suggest:
- One caller much more sensitive than others
- Potential caller-specific artifacts
- Worth checking individual caller counts (columns 36-42)

## Example Use Cases

### Find high-confidence gene fusions

```r
df %>%
  filter(
    TYPE == "BND",
    grepl("in frame", fusion),
    high_quality_evidence == TRUE,
    max_split_reads >= 5
  ) %>%
  select(TUMOR_ID, gene1, gene2, fusion,
         manta_split_reads, max_split_reads,
         NumCallersPass, high_quality_evidence)
```

### Identify variants with discordant callers

```r
# High max but low median suggests only one caller sees high count
discordant <- df %>%
  filter(
    max_split_reads >= 10,
    median_split_reads < 5
  ) %>%
  select(TUMOR_ID, TYPE, gene1, gene2,
         delly_split, manta_split, svaba_split,
         max_split_reads, median_split_reads,
         NumCallers)
```

### Compare MANTA-only vs MAX approach

```r
df %>%
  mutate(
    manta_sufficient = (manta_split_reads >= 3 & manta_paired_reads >= 5),
    max_approach = (max_split_reads >= 3 & max_paired_reads >= 5),
    max_adds_variants = max_approach & !manta_sufficient
  ) %>%
  count(manta_sufficient, max_approach, max_adds_variants)
```

## Quality Control

### Check for potential issues:

```r
# Variants with evidence but failed filters
df %>%
  filter(
    max_split_reads >= 5,
    NumCallersPass == 0
  )

# Very high counts (potential artifacts)
df %>%
  filter(max_split_reads > 200 | max_paired_reads > 200)

# Single caller only
df %>%
  filter(NumCallers == 1) %>%
  count(Callers)
```

## Integration with Original Data

To get full information including VAF and normal sample counts:

```r
# Read both files
depth <- read_csv("tempoSVDepth.csv")
full <- read_csv("tempoSVOutput.csv")

# Merge (they have same row order)
combined <- bind_cols(
  depth,
  full %>% select(t_svaba_VAF, n_svaba_VAF, # VAF columns
                  t_delly_JuncVAF, n_delly_JuncVAF,
                  starts_with("n_"))  # All normal sample columns
)

# Filter: high evidence + somatic + clonal
drivers <- combined %>%
  filter(
    high_quality_evidence == TRUE,
    t_svaba_VAF >= 0.15,
    n_svaba_VAF < 0.05,
    !is.na(CC_Tumour_Types)  # Known cancer gene
  )
```

## Column Name Quick Reference

**For filtering in Excel:**
- Column U: `manta_paired_reads`
- Column V: `manta_split_reads`
- Column W: `max_paired_reads`
- Column X: `max_split_reads`
- Column AD: `multi_evidence_type`
- Column AI: `high_quality_evidence`

**For R/tidyverse:**
Just use column names directly (case-sensitive).

## Files in This Directory

- `tempoSVOutput.csv` - Original TEMPO output (56 columns)
- `tempoSVDepth.csv` - This file (42 columns)
- `compute_depth_aggregates.R` - Script that created this file
- `tempoSVDepth_README.md` - This documentation
- `AGGREGATING_READ_COUNTS.md` - Detailed explanation of aggregation methods
- `READ_COUNT_SUMMARY.csv` - Quick Q&A reference
