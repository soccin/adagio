# Gene resources for the per-pair QC pages (qcgenes)

`buildQCGenes.R` builds the gene lists and gene-to-target maps that the
per-pair QC pages of `scripts/qcReport02.R` use for the missed-variant
likelihood panels (`scripts/rsrc/qc_pair_data.R`, `gene_mvlh`).

The outputs are not stored in git. They are on shared storage:

    /data1/core001/work/bic/socci/Resources/QCGenes/<version>/

`QC_GENES_DIR` in `scripts/rsrc/qc_pair_data.R` names the version in
use; `qcReport02.R --genes=DIR` overrides it. The folder's README.md
records where each source file came from.

## Sources (in `<version>/sources/`)

| File | Source | Use |
|---|---|---|
| `oncokb_cancerGeneList_<yymmdd>.tsv` | OncoKB cancer gene list, `https://www.oncokb.org/api/v1/utils/cancerGeneList.txt` | tumor genes; the GRCh37 transcript of each gene |
| `hmf_DriverGenePanel.38_oncoanalyser3.0.0.tsv` | Hartwig driver gene panel shipped with oncoanalyser 3.0.0 | germline genes (`HMF_GERMLINE`): those Hartwig reports for germline variants. Built but not used: the pages show tumors only (Tempo is somatic) |
| `IntOGen-Drivers-<date>_Compendium_Cancer_Genes.tsv` | IntOGen driver compendium, `https://www.intogen.org/download` (CC0) | drivers by cancer type (OncoTree codes), marked on the tumor panel |
| `oncotree_tumorTypes_<release>_<yymmdd>.json` | `https://oncotree.mskcc.org/api/tumorTypes?version=oncotree_latest_stable` | OncoTree parents, so READ also matches COADREAD |

Hartwig's panel is in their 5.5 GB resource bundle; the copy used here
is the stock oncoanalyser 3.0.0 file as committed to
`github.com/Clinical-Genomics/reference-files`
(`oncoflow/oncoanalyser/DriverGenePanel.38.tsv` at commit
`aa4f699ced23b852490727c10b475afd5b46bd6c`; the next commit there adds
TRIM28, which is not stock). Gene names and report flags do not depend
on the genome build. Germline genes are those with any of
`reportGermlineVariant`, `reportGermlineHotspot`,
`reportGermlineDeletion`, `reportGermlineDisruption` not `NONE`, as in
hmf-common `DriverGene.reportGermline()`.

OncoKB's terms of use cover academic use; check them before putting
the list or files derived from it in a public repository. That is why
these files are kept outside git.

## Build

```
sbatch <wrapper that runs:>
Rscript scripts/qcgenes/buildQCGenes.R \
    --src=<version>/sources --out=<version> --assay=WES_IDT_v2 \
    --gtf=/data1/core001/rsrc/genomic/mskcc-igenomes/grch37/gencode/gencode.v31lift37.basic.annotation.protein_coding.gtf \
    --targets=/data1/core001/rsrc/genomic/mskcc-igenomes/grch37/targets/IDT_Exome_v2_FP_b37_targets.plus5bp.bed
```

The GTF is about 0.9 GB: run it as a job (20 s, 4 GB). `--targets` must
be the BED Tempo gives Alfred (padded by 5 bp), so the target IDs match
Alfred's per-target coverage (`Chr:Start-End`, 0-based start).

## Outputs

| File | Contents |
|---|---|
| `genes_<ASSAY>.tsv` | one row per gene: `ONCOKB`, `ONCOKB_TYPE`, `IMPACT`, `HMF_SOMATIC`, `HMF_GERMLINE`, the transcript and how it was chosen (`HOW`), `CHROM`, `CDS_BASES`, `CDS_BASES_IN_TARGETS`, `N_TARGETS`, `FRAC_CDS_IN_TARGETS` |
| `gene_targets_<ASSAY>.tsv.gz` | `GENE`, `TARGET`, `BASES`: the gene's coding bases in each target |
| `intogen_drivers.tsv` | `GENE`, `CANCER_TYPE` (OncoTree code), `COHORTS`, `MAX_PCT_SAMPLES`, `ROLE` |
| `oncotree.tsv` | `CODE`, `PARENT`, `LEVEL`, `NAME` |

Transcript per gene: OncoKB's GRCh37 transcript when the GTF has it,
else the longest CDS among transcripts with a CCDS tag, else the
longest. The Y copies of pseudoautosomal genes are dropped. Exact
repeats in the target BED are kept once; padded neighbors can overlap
by a few bases, which then count in both targets.

## Version v261125 (built 2026-11-25)

- 1,282 genes: 1,247 OncoKB, 69 Hartwig germline (68 of them also in
  OncoKB; RHBDF2 is not).
- 976 genes take OncoKB's transcript, 276 one chosen by name. 30 have no
  CDS in GENCODE v31: histone genes renamed since 2019 (H3C1 ...),
  SEPTIN5/6/9 (SEPT5/6/9 there), immunoglobulin and T-cell receptor
  loci, non-coding entries (TERC, MDS2, ...), GAS7, RNF213.
- IDT v2 targets hold all coding bases of the median gene; 8 genes have
  under 95%: NUTM2D 68%, BAALC 81%, PDE4DIP 86%, NCOA4 88%, RAD51B 90%,
  MKNK1 91%, CHEK2 93%, and PTP4A1 0% (none of its OncoKB transcript's
  coding bases; left out of the panels, which need 50%).
