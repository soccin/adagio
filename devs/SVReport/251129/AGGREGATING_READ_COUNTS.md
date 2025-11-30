# Aggregating Read Counts Across Callers - Analysis and Recommendations

## Question

Can we combine read counts from different callers (DELLY, MANTA, SvABA) into:
1. **Total tumor paired-end/discordant reads**
2. **Total tumor split/junction reads**

## Short Answer

**Simple summing is NOT recommended** because callers count the same underlying reads, leading to massive overcounting.

**Better approaches:**
1. **Maximum value** across callers (most sensitive detection)
2. **Median value** across callers (central tendency)
3. **Agreement indicator** (how many callers see evidence)
4. **Use existing NumCallers/NumCallersPass** (already does this conceptually)

---

## The Problem: Callers Count the Same Reads

### Evidence from Actual Data

Looking at row 5 (variant called by all 4 callers):

| Metric | DELLY | MANTA | SvABA | Analysis |
|--------|-------|-------|-------|----------|
| **Paired-end variant** | t_delly_DV = 8 | t_manta_PR = "138,**8**" | t_svaba_DR = 6 | DELLY and MANTA see **identical count (8)**! |
| **Split/junction variant** | t_delly_RV = 6 | t_manta_SR = "176,**4**" | t_svaba_SR = 4 | MANTA and SvABA agree (**4**), DELLY slightly higher (6) |
| **Total variant reads** | PE: 8, Split: 3 | - | t_svaba_AD = 10 | SvABA AD (10) ≈ DR (6) + SR (4) |

**Key observations:**
1. **DELLY and MANTA count identical paired-end reads** (both = 8)
2. **MANTA and SvABA count similar split reads** (both = 4)
3. **SvABA's allele depth (AD) is the sum of its own DR + SR**
4. All callers analyze the **same BAM file**, so they see the **same physical reads**

### What This Means

If you sum: 8 (DELLY) + 8 (MANTA) + 6 (SvABA) = **22 paired-end reads**

But the **actual count is ~8 reads** that all three callers detected!

**Summing gives a 2.75x overcount.**

---

## Understanding Read Count Fields

### Paired-End / Discordant Reads

**Definition**: Read pairs with wrong orientation or unexpected distance

| Excel | Field | Caller | What It Counts |
|-------|-------|--------|----------------|
| **AM** | t_delly_DV | DELLY | Tumor variant pairs |
| **AD** | t_manta_PR | MANTA | Tumor paired reads (extract ALT from "REF,ALT") |
| **AP** | t_svaba_DR | MANTA | Tumor discordant reads |

**These count overlapping/identical reads!**

### Split / Junction Reads

**Definition**: Reads that span across the exact breakpoint junction

| Excel | Field | Caller | What It Counts |
|-------|-------|--------|----------------|
| **AO** | t_delly_RV | DELLY | Tumor variant junction reads |
| **AE** | t_manta_SR | MANTA | Tumor split reads (extract ALT from "REF,ALT") |
| **AG** | t_svaba_SR | SvABA | Tumor spanning reads* |

*Note: SvABA's "spanning reads" might be slightly different from pure split reads

**These also count overlapping/identical reads!**

### SvABA's Allele Depth (AD)

| Excel | Field | What It Is |
|-------|-------|------------|
| **AF** | t_svaba_AD | **Total variant reads** (DR + SR combined) |

**Do NOT add this to other counts** - it's already a sum!

---

## Recommended Approaches

### Approach 1: Maximum Value (RECOMMENDED)

Take the highest count across callers = "most sensitive caller detected this many"

**Formulas for Excel:**

**Tumor Paired-End Reads:**
```excel
=MAX(
  AM2,
  VALUE(RIGHT(AD2,LEN(AD2)-FIND(",",AD2))),
  AP2
)
```
Where:
- AM2 = t_delly_DV
- AD2 = t_manta_PR (extracts ALT count after comma)
- AP2 = t_svaba_DR

**Tumor Split Reads:**
```excel
=MAX(
  AO2,
  VALUE(RIGHT(AE2,LEN(AE2)-FIND(",",AE2))),
  AG2
)
```
Where:
- AO2 = t_delly_RV
- AE2 = t_manta_SR (extracts ALT count after comma)
- AG2 = t_svaba_SR

**Interpretation**: "At least this many reads support the variant (from most sensitive caller)"

### Approach 2: Median Value

Take the middle value = "typical evidence level"

**Excel formula** (for paired-end):
```excel
=MEDIAN(
  AM2,
  VALUE(RIGHT(AD2,LEN(AD2)-FIND(",",AD2))),
  AP2
)
```

**Interpretation**: "Central tendency of evidence across methods"

### Approach 3: Weighted Average by Caller Reliability

If you know certain callers are more reliable:

```excel
=(AM2*0.4 + VALUE(RIGHT(AD2,LEN(AD2)-FIND(",",AD2)))*0.4 + AP2*0.2)
```

Example weights:
- DELLY: 40% (comprehensive, well-established)
- MANTA: 40% (excellent for somatic, high-quality filtering)
- SvABA: 20% (assembly-based, different approach)

### Approach 4: Use Existing Summary Fields

**The output already has aggregated metrics!**

| Column | Field | What It Shows |
|--------|-------|---------------|
| R | NumCallers | How many callers detected it (1-4) |
| S | NumCallersPass | How many callers passed filters (0-4) |

**These effectively answer**: "How many independent methods see evidence?"

**For read depth**, use the **most reliable single caller**:
- **MANTA** (columns AD, AE) - excellent quality filtering (MAPQ ≥30)
- **DELLY** (columns AM, AO) - comprehensive metrics

---

## Practical Implementation

### Option A: Simple - Use MANTA Counts

MANTA has the cleanest format and strictest quality (MAPQ ≥30).

**Just use:**
- **Column AE (t_manta_SR)** - extract ALT count = tumor split reads
- **Column AD (t_manta_PR)** - extract ALT count = tumor paired reads

**Excel formulas:**
```excel
# Column "MANTA_Split_Reads"
=VALUE(RIGHT(AE2,LEN(AE2)-FIND(",",AE2)))

# Column "MANTA_Paired_Reads"
=VALUE(RIGHT(AD2,LEN(AD2)-FIND(",",AD2)))
```

### Option B: Maximum Across Callers

Create new columns showing max evidence:

```excel
# Column "Max_Tumor_Split"
=MAX(
  IF(ISNUMBER(AO2),AO2,0),
  IF(ISNUMBER(VALUE(RIGHT(AE2,LEN(AE2)-FIND(",",AE2)))),VALUE(RIGHT(AE2,LEN(AE2)-FIND(",",AE2))),0),
  IF(ISNUMBER(AG2),AG2,0)
)

# Column "Max_Tumor_Paired"
=MAX(
  IF(ISNUMBER(AM2),AM2,0),
  IF(ISNUMBER(VALUE(RIGHT(AD2,LEN(AD2)-FIND(",",AD2)))),VALUE(RIGHT(AD2,LEN(AD2)-FIND(",",AD2))),0),
  IF(ISNUMBER(AP2),AP2,0)
)
```

The IF statements handle NA/missing values when a caller didn't run.

### Option C: Agreement Score

Show how many callers see at least N reads:

```excel
# Column "Callers_With_5plus_Split_Reads"
=(IF(AO2>=5,1,0) + IF(VALUE(RIGHT(AE2,LEN(AE2)-FIND(",",AE2)))>=5,1,0) + IF(AG2>=5,1,0))
```

Interpretation: "2" means 2 out of 3 callers see ≥5 split reads

---

## What NOT To Do

### ❌ DO NOT: Simple Sum

```excel
# WRONG - massive overcounting!
=AM2 + VALUE(RIGHT(AD2,LEN(AD2)-FIND(",",AD2))) + AP2
```

This counts the same reads 2-3 times.

### ❌ DO NOT: Add SvABA AD to others

```excel
# WRONG - AD is already a sum!
=AF2 + AM2 + ...
```

SvABA's AD already includes DR + SR.

### ❌ DO NOT: Mix tumor and normal

```excel
# WRONG - compares apples and oranges
=AM2 + AR2  # t_delly_DV + n_delly_DV
```

Tumor and normal should be analyzed separately.

---

## Recommended New Columns to Add

If you're creating a summary spreadsheet, add these calculated columns:

| New Column | Formula | What It Shows |
|------------|---------|---------------|
| **Split_Reads_Max** | MAX(AO, MANTA_SR_ALT, AG) | Highest split read count |
| **Paired_Reads_Max** | MAX(AM, MANTA_PR_ALT, AP) | Highest paired-end count |
| **Split_Reads_Median** | MEDIAN(AO, MANTA_SR_ALT, AG) | Typical split read count |
| **Paired_Reads_Median** | MEDIAN(AM, MANTA_PR_ALT, AP) | Typical paired-end count |
| **Total_Evidence_Max** | Split_Max + Paired_Max | Maximum total reads |
| **Callers_Agree_High_Evidence** | COUNT(callers with ≥5 reads) | Agreement indicator |

---

## Example Analysis

**Variant from row 5:**

| Metric | DELLY | MANTA | SvABA | MAX | MEDIAN | SUM (wrong!) |
|--------|-------|-------|-------|-----|--------|--------------|
| Paired-end | 8 | 8 | 6 | **8** | **8** | 22 |
| Split reads | 6 | 4 | 4 | **6** | **4** | 14 |

**Interpretation:**
- **MAX approach**: 8 paired + 6 split = 14 total reads maximum
- **MEDIAN approach**: 8 paired + 4 split = 12 total reads typical
- **SUM (WRONG)**: 22 paired + 14 split = 36 total (250% overcount!)

**Recommended summary**: "8 paired-end reads and 4-6 split reads support this variant"

---

## Biological Interpretation

### What Matters Most

1. **Multiple evidence types**: Both PE and SR present = strong call
2. **Multiple callers agree**: NumCallersPass ≥ 2
3. **High-quality reads**: MANTA uses MAPQ ≥30
4. **Consistent counts**: Callers seeing similar numbers = reliable

### Quality Thresholds Using MAX Values

| Max Split Reads | Max Paired Reads | Confidence |
|-----------------|------------------|------------|
| ≥5 | ≥10 | **Excellent** - strong, multi-type evidence |
| ≥3 | ≥5 | **Good** - meets standard thresholds |
| ≥2 | ≥3 | **Moderate** - minimal evidence |
| <2 | <3 | **Weak** - likely artifact or low coverage |

---

## Summary

**Key Points:**
1. **Callers count the same reads** - summing causes massive overcounting
2. **Use MAX or MEDIAN** - more accurate representation
3. **MANTA alone is often sufficient** - cleanest format, best quality filtering
4. **NumCallersPass already summarizes consensus** - use this for agreement
5. **Focus on evidence diversity** - both PE and SR better than high count of one type

**Simplest approach for biologists:**
- Use **MANTA** split reads (column AE, ALT count) as primary metric
- Check **NumCallersPass** (column S) for confidence
- Verify both paired AND split reads present for strongest calls
