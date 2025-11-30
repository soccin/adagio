# Reconciliation Notes: Documentation vs Actual Output

## Summary of Discrepancy

The existing documentation files (`tempoSVOutputColumnDesc.csv` and `TEMPO_SV_OUTPUT.md`) describe the **raw VCF output** from the four structural variant callers (BRASS, DELLY, MANTA, SvABA), but the actual file `tempoSVOutput.csv` is a **highly processed and summarized** output.

## What Changed Between Raw VCF and Final Output

### Columns REMOVED from raw VCF (not in final CSV)

The following detailed technical columns from the raw callers are **NOT** in the final output:

#### BRASS fields (not present):
- brass_BAS (assembly score)
- brass_SVCLASS (SV class)
- brass_MATEID, brass_BKDIST, brass_FFV, brass_OCC
- brass_SID, brass_GENE, brass_TID, brass_AS
- brass_EPH, brass_PH, brass_RGN, brass_RGNNO, brass_RGNC
- brass_TSRDS, brass_TRDS

**These were transformed into**: fusion, gene1, gene2, site1, site2 annotations

#### DELLY fields (partially removed):
- delly_CIEND, delly_CIPOS (confidence intervals)
- delly_MAPQ (mapping quality)
- delly_CT (connection type)
- delly_IMPRECISE
- delly_SVMETHOD
- delly_RDRATIO (transformed into VAF calculations)
- delly_SOMATIC, delly_AC, delly_AN
- delly_GQ, delly_FT
- delly_RC, delly_RCL, delly_RCR
- delly_CN

**What was kept**: delly_PE, delly_SR, delly_DR, delly_DV, delly_RR, delly_RV, delly_CONSENSUS

#### MANTA fields (partially removed):
- manta_IMPRECISE
- manta_CIPOS, manta_CIEND
- manta_MATEID
- manta_SVINSLEN, manta_SVINSSEQ
- manta_BND_DEPTH, manta_MATE_BND_DEPTH
- manta_SOMATIC
- manta_SOMATICSCORE

**What was kept**: manta_PR, manta_SR

#### SvABA fields (partially removed):
- svaba_DISC_MAPQ
- svaba_NUMPARTS
- svaba_MATEID
- svaba_MAPQ
- svaba_SCTG (contig ID)
- svaba_NM, svaba_MATENM
- svaba_SPAN
- svaba_INSERTION
- svaba_IMPRECISE
- svaba_EVDNC
- svaba_LR, svaba_PL, svaba_GQ, svaba_LO
- svaba_DP

**What was kept**: svaba_AD, svaba_DR, svaba_SR

### Columns ADDED in final output (not in raw VCF)

#### Sample identifiers
- TUMOR_ID
- NORMAL_ID
- UUID

#### High-level annotations
- TYPE (standardized SV type)
- fusion (protein fusion predictions)
- gene1, gene2 (simplified gene annotations)
- site1, site2 (human-readable genomic locations)
- CHROM_A, START_A, END_A, CHROM_B, START_B, END_B (standardized coordinates)
- STRANDS (orientation)

#### Repeat annotations
- repeat.site1
- repeat.site2

#### Consensus calling
- Callers (which programs called it)
- NumCallers
- NumCallersPass

#### Calculated VAF metrics (NEW - not in raw VCF)
- t_delly_SpanVAF
- t_delly_JuncVAF
- n_delly_SpanVAF
- n_delly_JuncVAF
- t_svaba_VAF
- n_svaba_VAF
- t_manta_JuncVAF

These are **calculated from raw read counts** using formulas like:
- delly_SpanVAF = delly_DV / (delly_DR + delly_DV)
- delly_JuncVAF = delly_RV / (delly_RR + delly_RV)
- svaba_VAF = svaba_AD / svaba_DP
- manta_JuncVAF = calculated from manta_SR

#### Tumor/Normal separation
All read count fields now separated with prefixes:
- **t_** prefix for tumor sample
- **n_** prefix for normal sample

Examples:
- Raw VCF had: `delly_DR`, `delly_DV` (both samples mixed)
- Final CSV has: `t_delly_DR`, `t_delly_DV`, `n_delly_DR`, `n_delly_DV`

#### Cancer Gene Census annotations (CC_)
- CC_Chr_Band
- CC_Tumour_Types(Somatic)
- CC_Cancer_Syndrome
- CC_Mutation_Type
- CC_Translocation_Partner

#### Database of Genomic Variants (DGv_)
- DGv_Name-DGv_VarType-site1
- DGv_Name-DGv_VarType-site2

## Processing Pipeline Inference

Based on these changes, the TEMPO pipeline appears to:

1. **Run four callers** (BRASS, DELLY, MANTA, SvABA) on paired tumor/normal BAM files
2. **Generate raw VCF files** with all technical details (documented in `TEMPO_SV_OUTPUT.md`)
3. **Merge/consensus call** across callers
4. **Annotate** with:
   - Gene databases (BRASS annotations → gene1, gene2, site1, site2, fusion)
   - Cancer Gene Census
   - Database of Genomic Variants
   - Repeat masker
5. **Calculate VAF** from raw read counts
6. **Simplify and filter** to most relevant metrics
7. **Separate tumor and normal** metrics with t_/n_ prefixes
8. **Output final CSV** (`tempoSVOutput.csv`)

## Implications for Users

### For computational analysis:
- The **final CSV** is optimized for clinical/biological interpretation
- If you need raw technical details (MAPQ, CIPOS, assembly scores), you need to access the **intermediate VCF files**
- VAF is pre-calculated - no need to compute from read counts
- Annotations are pre-integrated

### For biological interpretation:
- The **final CSV** has everything you need
- Focus on VAF, gene annotations, and caller consensus
- No need to understand VCF format or raw caller outputs
- Use `tempoSVOutput_ColumnGuide.csv` for column descriptions

### For troubleshooting:
- If you need to verify a call or understand why something was filtered, you need:
  1. Raw VCF files from each caller
  2. The merge/consensus calling logic
  3. Filter criteria applied
- The final CSV doesn't show *why* a variant passed/failed filters

## File Organization Summary

### Files that document the ACTUAL output (use these):
1. **tempoSVOutput_ColumnGuide.csv** - Column-by-column descriptions of actual output
2. **GUIDE_FOR_BIOLOGISTS.md** - Comprehensive interpretation guide
3. **QUICK_REFERENCE.md** - One-page quick reference
4. **RECONCILIATION_NOTES.md** - This file

### Files that document RAW VCF (reference only):
1. **tempoSVOutputColumnDesc.csv** - Original raw VCF column descriptions
2. **TEMPO_SV_OUTPUT.md** - Detailed technical docs on raw caller outputs

**These are still valuable** for understanding:
- What the raw callers produce
- Technical details of each caller
- How to interpret intermediate VCF files
- What information was available before summarization

## Recommendations

### For biologists working with tempoSVOutput.csv:
1. Start with **QUICK_REFERENCE.md**
2. Read **GUIDE_FOR_BIOLOGISTS.md** for comprehensive understanding
3. Keep **tempoSVOutput_ColumnGuide.csv** open while analyzing data
4. Refer to **TEMPO_SV_OUTPUT.md** only if you need to understand technical details

### For bioinformaticians:
1. Understand that **tempoSVOutput.csv is summarized** - not raw VCF
2. If you need raw data, request intermediate VCF files
3. Use **TEMPO_SV_OUTPUT.md** to understand what was in raw VCFs
4. Use **tempoSVOutput_ColumnGuide.csv** to understand transformations

### For pipeline developers:
1. Document the processing steps between raw VCF and final CSV
2. Document VAF calculation formulas
3. Document filter criteria (what makes NumCallersPass increment)
4. Consider providing both raw VCF and processed CSV outputs

## Missing Documentation

The following are still not fully documented:

1. **VAF calculation formulas** - inferred but not confirmed
2. **Filter criteria** - what makes a call "pass" for each caller?
3. **Fusion prediction algorithm** - how is "in frame" determined?
4. **Gene annotation source** - which version of which gene database?
5. **Coordinate system** - are these 0-based or 1-based? (appears 1-based from data)
6. **Repeat annotation source** - RepeatMasker? Which version?
7. **Merging logic** - how are coordinates merged when callers disagree?
8. **DGv annotation** - which version of DGv? How many entries trigger concern?

These would require access to:
- Pipeline source code
- Configuration files
- Database versions used
- Or communication with pipeline developers
