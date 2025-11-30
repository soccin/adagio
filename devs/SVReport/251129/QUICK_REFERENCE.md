# TEMPO SV Output - Quick Reference Card

## Essential Columns for First-Pass Review

| Column | What It Tells You | Good Values |
|--------|-------------------|-------------|
| **gene1, gene2** | Which genes are affected | Known cancer genes |
| **fusion** | Predicted fusion type | "in frame" is functional |
| **TYPE** | Variant type | BND (translocation) often important |
| **NumCallersPass** | Quality/confidence | >= 2 is reliable, >= 3 is excellent |
| **t_svaba_VAF** | % of tumor cells with variant | 0.15-0.50 is clonal/important |
| **n_svaba_VAF** | % of normal cells with variant | 0.00-0.02 (want zero = somatic) |
| **CC_Tumour_Types** | Known cancer gene? | If filled = known cancer involvement |

## Quick Filtering Strategy

### HIGH PRIORITY - Likely Driver Mutations
- NumCallersPass >= 2
- TYPE = BND (translocation)
- fusion contains "in frame"
- gene1 OR gene2 has entry in CC_Tumour_Types
- t_svaba_VAF >= 0.15 (or t_delly_JuncVAF >= 0.15)
- n_svaba_VAF < 0.05 (or n_delly_JuncVAF < 0.05)
- DGv columns mostly blank

### MEDIUM PRIORITY - Tumor Suppressor Loss
- CC_Mutation_Type contains "TSG"
- site1 or site2 mentions "Exon"
- NumCallersPass >= 2
- Tumor VAF >= 0.15, Normal VAF < 0.05

### LOW PRIORITY - Likely Artifacts/Benign
- NumCallersPass = 0 or 1
- Normal VAF > 0.40 (germline)
- Both repeat.site1 and repeat.site2 filled
- Tumor VAF < 0.08
- Many DGv entries

## Understanding VAF (Variant Allele Fraction)

VAF = What fraction of cells have the mutation

### Tumor VAF (t_*_VAF columns)
- **0.40-0.50**: Clonal - in most tumor cells (IMPORTANT)
- **0.15-0.35**: Subclonal - in subset of cells (moderate)
- **<0.10**: Rare - may be artifact (low priority)

### Normal VAF (n_*_VAF columns)
- **0.00-0.02**: True somatic mutation (GOOD)
- **0.05-0.15**: Possible contamination (check)
- **>0.40**: Germline/inherited (not tumor-specific)

## Read Count Evidence

Higher numbers = stronger evidence

### Key columns to check:
- **delly_PE**: Paired-end support (need 3+ for DEL, 5+ for BND)
- **t_manta_SR**: Tumor split reads - format "ref,alt"
  - Example: "97,19" = 19 reads support variant
- **t_svaba_AD**: Direct variant read count

### What you want to see:
- High counts in tumor (t_*)
- Zero or low counts in normal (n_*)

## Gene Annotation Quick Guide

### fusion column
- **"Protein Fusion: in frame {GENE1:GENE2}"** = Functional fusion protein (HIGH IMPACT)
- **"out of frame"** = Non-functional fusion (still disrupts genes)
- **Blank** = No fusion (simple disruption)

### site1/site2 columns
- **"Exon of GENE"** = Breaks coding sequence (HIGH IMPACT)
- **"Intron of GENE"** = Breaks between exons (MODERATE)
- **"IGR"** = Intergenic region (LOW, may affect regulation)
- **"UTR"** = Untranslated region (MODERATE)

### CC_Mutation_Type (Cancer Gene Census)
- **"oncogene"** = Activation drives cancer
- **"TSG"** = Tumor suppressor, loss drives cancer
- **"fusion"** = Known to form oncogenic fusions
- **Blank** = Not a known cancer gene

## Structural Variant Types (TYPE column)

- **DEL** (Deletion): DNA segment removed
- **DUP** (Duplication): DNA segment copied
- **INV** (Inversion): DNA segment flipped
- **BND** (Breakend/Translocation): DNA from different regions joined

**Most clinically relevant are usually BND affecting cancer genes**

## Caller Information

### The 4 Detection Programs
1. **brass**: Assembly-based (Sanger) - high quality
2. **delly**: Paired-end/split-read - good sensitivity
3. **manta**: Illumina's caller - very reliable
4. **svaba**: Assembly-based - good for complex events

### Callers column
Shows which programs detected it: "brass,manta,svaba"

### NumCallers vs NumCallersPass
- **NumCallers**: How many found it (1-4)
- **NumCallersPass**: How many gave it high quality (0-4)
- **NumCallersPass is more stringent**

## Common Patterns

### Classic Driver Fusion
```
TYPE: BND
fusion: Protein Fusion: in frame {BCR:ABL1}
NumCallersPass: 3-4
t_svaba_VAF: 0.40-0.50
n_svaba_VAF: 0.00
CC_Tumour_Types: [filled with cancer types]
CC_Translocation_Partner: [lists known partners]
```

### Likely Artifact
```
NumCallersPass: 0-1
Callers: delly (alone)
t_svaba_VAF: 0.03
repeat.site1: AluSq
repeat.site2: L1MB
DGv_Name-site1: [many entries]
```

### Germline Variant
```
t_svaba_VAF: 0.48
n_svaba_VAF: 0.46
(present equally in tumor and normal)
```

## Action Items Checklist

For each high-priority variant:

- [ ] Verify it's somatic (normal VAF ~0, tumor VAF >0.1)
- [ ] Check if genes are in cancer databases (CC_ columns)
- [ ] For fusions, confirm in-frame and check known partners
- [ ] Verify strong evidence (NumCallersPass >=2, good read counts)
- [ ] Check if region has common variants (DGv columns)
- [ ] Look up genes in COSMIC/literature for your cancer type
- [ ] Consider RNA-seq validation if critical fusion
- [ ] Integrate with copy number and mutation data

## Where to Get More Information

**Detailed Column Guide**: `tempoSVOutput_ColumnGuide.csv`
**Full Biologist Guide**: `GUIDE_FOR_BIOLOGISTS.md`
**Technical Details**: `TEMPO_SV_OUTPUT.md`

**Online Resources**:
- Cancer Gene Census: https://cancer.sanger.ac.uk/census
- COSMIC Fusions: https://cancer.sanger.ac.uk/cosmic/fusion
- CIViC (Clinical Interpretations): https://civicdb.org
