#
# buildQCGenes.R
#
# Builds the gene resources of the per-pair QC pages (qcReport02.R,
# rsrc/qc_pair_*.R): the gene lists, the coding bases of each gene, and
# the exome targets that cover them. Run once per gene list release and
# target set; see README.md in this folder.
#
# Inputs (in --src): the OncoKB cancer gene list, Hartwig's driver gene
# panel (oncoanalyser 3.0.0), the IntOGen driver compendium and the
# OncoTree tumor types. Also the GENCODE GRCh37 GTF (--gtf) and the
# padded target BED that Tempo gives Alfred (--targets).
#
# Outputs (in --out; <ASSAY> from --assay, e.g. WES_IDT_v2):
#   genes_<ASSAY>.tsv      one row per gene: lists it is on, the
#                          transcript used, coding bases and how many
#                          of them are in targets
#   gene_targets_<ASSAY>.tsv.gz
#                          GENE, TARGET (Chr:Start-End as in Alfred's TC
#                          section), BASES (coding bases of the gene in
#                          the target)
#   intogen_drivers.tsv    GENE, CANCER_TYPE (OncoTree code), COHORTS,
#                          MAX_PCT_SAMPLES, ROLE
#   oncotree.tsv           CODE, PARENT, LEVEL, NAME
#
# The GTF is large (about 0.9 GB): submit with sbatch.
#

usage <- function() {
    cat("
Usage: Rscript buildQCGenes.R --src=DIR --out=DIR --gtf=FILE --targets=FILE --assay=NAME

  --src=DIR      folder with the downloaded source files (see README.md)
  --out=DIR      output folder
  --gtf=FILE     GENCODE GRCh37 GTF with CDS records
  --targets=FILE target BED as given to Alfred (0-based, padded)
  --assay=NAME   assay label for the target-specific file names
                 (the QC database label, e.g. WES_IDT_v2)
")
}

args <- commandArgs(trailingOnly = TRUE)
if (any(args %in% c("-h", "--help"))) {
    usage()
    quit(status = 0)
}
opt <- as.list(setNames(sub("^--[A-Za-z-]+=", "", args), sub("^--([A-Za-z-]+)=.*", "\\1", args)))
need <- c("src", "out", "gtf", "targets", "assay")
if (!all(need %in% names(opt))) {
    usage()
    stop("Missing option(s): ", paste(setdiff(need, names(opt)), collapse = ", "), call. = FALSE)
}

suppressPackageStartupMessages({
    library(tidyverse)
    library(glue)
})

src_file <- function(pattern) {
    f <- fs::dir_ls(opt$src, regexp = pattern)
    if (length(f) != 1) stop(glue("Expected one file matching {pattern} in {opt$src}, found {length(f)}"), call. = FALSE)
    f
}

#
# Gene lists
#
oncokb <- read_tsv(src_file("oncokb_cancerGeneList.*\\.tsv$"), show_col_types = FALSE) |>
    transmute(
        GENE = `Hugo Symbol`,
        ONCOKB = TRUE,
        ONCOKB_TYPE = `Gene Type`,
        IMPACT = `MSK-IMPACT` == "Yes",
        ONCOKB_TRANSCRIPT = `GRCh37 Isoform`
    )

# Hartwig: a gene is reported somatic or germline as in hmf-common
# DriverGene.reportSomatic() and reportGermline()
hmf <- read_tsv(src_file("hmf_DriverGenePanel.*\\.tsv$"), col_types = cols(.default = "c"), show_col_types = FALSE) |>
    transmute(
        GENE = gene,
        HMF_SOMATIC = if_any(c(reportMissense, reportNonsense, reportSplice, reportSomaticHotspot), \(x) x == "TRUE"),
        HMF_GERMLINE = if_any(c(reportGermlineVariant, reportGermlineHotspot, reportGermlineDeletion,
                                reportGermlineDisruption), \(x) x != "NONE")
    )

hmfReported <- hmf |>
    filter(HMF_SOMATIC | HMF_GERMLINE)
genes <- full_join(oncokb, hmfReported, by = "GENE") |>
    mutate(across(c(ONCOKB, IMPACT, HMF_SOMATIC, HMF_GERMLINE), \(x) coalesce(x, FALSE)))
message(glue("Genes: {nrow(genes)} ({sum(genes$ONCOKB)} OncoKB, {sum(genes$HMF_GERMLINE)} Hartwig germline)"))

intogen <- read_tsv(src_file("Compendium_Cancer_Genes\\.tsv$"), show_col_types = FALSE) |>
    summarize(
        COHORTS = n_distinct(COHORT),
        MAX_PCT_SAMPLES = round(100 * max(`%_SAMPLES_COHORT`), 1),
        ROLE = first(ROLE),
        .by = c(SYMBOL, CANCER_TYPE)
    ) |>
    rename(GENE = SYMBOL) |>
    arrange(CANCER_TYPE, desc(MAX_PCT_SAMPLES))

oncotree <- jsonlite::read_json(src_file("oncotree_tumorTypes.*\\.json$")) |>
    map(\(x) tibble(CODE = x$code, PARENT = x$parent %||% NA_character_, LEVEL = x$level, NAME = x$name)) |>
    list_rbind()

#
# Coding exons (CDS) from GENCODE, one transcript per gene: OncoKB's
# GRCh37 transcript when the GTF has it; otherwise the transcript with
# the longest CDS among those with a CCDS tag, else among all
#
message("Reading CDS records from the GTF")
gtfCols <- c("CHROM", "SOURCE", "FEATURE", "START", "END", "SCORE", "STRAND", "FRAME", "ATTR")
# The Y copies of pseudoautosomal genes (transcript IDs ending _PAR_Y)
# are dropped, so their bases count once, on X
cds <- read_tsv(opt$gtf, comment = "#", col_names = gtfCols, col_types = "cccii-c-c", show_col_types = FALSE,
                progress = FALSE) |>
    filter(FEATURE == "CDS", !str_detect(ATTR, 'transcript_id "[^"]+_PAR_Y"')) |>
    mutate(
        CHROM = str_remove(CHROM, "^chr"),
        GTF_GENE = str_extract(ATTR, 'gene_name "([^"]+)"', group = 1),
        TRANSCRIPT = str_extract(ATTR, 'transcript_id "(ENST\\d+)', group = 1),
        CCDS = str_detect(ATTR, 'tag "CCDS"'),
        # GTF is 1-based closed; BED is 0-based half-open
        START = START - 1L
    ) |>
    select(CHROM, START, END, GTF_GENE, TRANSCRIPT, CCDS)

txLength <- cds |>
    summarize(CDS_BASES = sum(END - START), CCDS = any(CCDS), .by = c(GTF_GENE, TRANSCRIPT, CHROM))

txIds <- txLength |>
    distinct(TRANSCRIPT)
byOncokb <- genes |>
    filter(!is.na(ONCOKB_TRANSCRIPT)) |>
    inner_join(txIds, by = c("ONCOKB_TRANSCRIPT" = "TRANSCRIPT")) |>
    transmute(GENE, TRANSCRIPT = ONCOKB_TRANSCRIPT, HOW = "OncoKB transcript")
byName <- genes |>
    anti_join(byOncokb, by = "GENE") |>
    inner_join(txLength, by = c("GENE" = "GTF_GENE"), relationship = "many-to-many") |>
    arrange(desc(CCDS), desc(CDS_BASES)) |>
    distinct(GENE, .keep_all = TRUE) |>
    transmute(GENE, TRANSCRIPT, HOW = if_else(CCDS, "longest CCDS transcript", "longest transcript"))
chosen <- bind_rows(byOncokb, byName) |>
    distinct(GENE, .keep_all = TRUE)
missing <- setdiff(genes$GENE, chosen$GENE)
message(glue("Transcripts: {sum(chosen$HOW == 'OncoKB transcript')} OncoKB, {sum(chosen$HOW != 'OncoKB transcript')} ",
             "by name; no CDS in the GTF for {length(missing)}: {str_c(missing, collapse = ', ')}"))

# Two genes may name one transcript (OncoKB aliases), so many-to-many
cdsRecords <- cds |>
    select(-GTF_GENE, -CCDS)
geneCds <- chosen |>
    inner_join(cdsRecords, by = "TRANSCRIPT", relationship = "many-to-many")

#
# Targets: the coding bases of each gene in each target
#
# Exact repeats in the BED (U2AF1's exons are listed twice) are kept
# once. Padded neighbors can overlap by a few bases; those bases count
# in both targets, so the fraction in targets is capped at 1.
targets <- read_tsv(opt$targets, col_names = c("CHROM", "T_START", "T_END"), col_types = "cii-",
                    show_col_types = FALSE) |>
    mutate(CHROM = str_remove(CHROM, "^chr")) |>
    distinct(CHROM, T_START, T_END) |>
    mutate(TARGET = str_c(CHROM, ":", T_START, "-", T_END))
overlapping <- targets |>
    arrange(CHROM, T_START) |>
    filter(T_START < lag(T_END), CHROM == lag(CHROM)) |>
    nrow()
message(glue("Targets: {nrow(targets)}, {overlapping} overlapping the one before"))

geneTargets <- geneCds |>
    inner_join(targets, by = join_by(CHROM, overlaps(START, END, T_START, T_END, bounds = "[)"))) |>
    mutate(BASES = pmin(END, T_END) - pmax(START, T_START)) |>
    summarize(BASES = sum(BASES), .by = c(GENE, TARGET)) |>
    arrange(GENE, TARGET)

inTargets <- geneTargets |>
    summarize(CDS_BASES_IN_TARGETS = sum(BASES), N_TARGETS = n(), .by = GENE)
geneSummary <- geneCds |>
    summarize(CHROM = first(CHROM), CDS_BASES = sum(END - START), .by = c(GENE, TRANSCRIPT, HOW)) |>
    left_join(inTargets, by = "GENE") |>
    mutate(CDS_BASES_IN_TARGETS = coalesce(CDS_BASES_IN_TARGETS, 0L), N_TARGETS = coalesce(N_TARGETS, 0L))

genesOut <- genes |>
    select(-ONCOKB_TRANSCRIPT) |>
    left_join(geneSummary, by = "GENE") |>
    mutate(
        CDS_BASES_IN_TARGETS = pmin(CDS_BASES_IN_TARGETS, CDS_BASES),
        FRAC_CDS_IN_TARGETS = round(CDS_BASES_IN_TARGETS / CDS_BASES, 4)
    ) |>
    arrange(GENE)

fs::dir_create(opt$out)
genesFile <- glue("genes_{opt$assay}.tsv")
targetsFile <- glue("gene_targets_{opt$assay}.tsv.gz")
write_tsv(genesOut, file.path(opt$out, genesFile), na = "")
write_tsv(geneTargets, file.path(opt$out, targetsFile))
write_tsv(intogen, file.path(opt$out, "intogen_drivers.tsv"))
write_tsv(oncotree, file.path(opt$out, "oncotree.tsv"), na = "")

capture <- genesOut |> filter(!is.na(CDS_BASES))
message(glue("Coding bases in targets: median {round(100 * median(capture$FRAC_CDS_IN_TARGETS), 1)}%; ",
             "{sum(capture$FRAC_CDS_IN_TARGETS < 0.95)} genes below 95%, ",
             "{sum(capture$FRAC_CDS_IN_TARGETS < 0.8)} below 80%"))
message(glue("Wrote {opt$out}: {genesFile} ({nrow(genesOut)}), {targetsFile} ({nrow(geneTargets)}), ",
             "intogen_drivers.tsv ({nrow(intogen)}), oncotree.tsv ({nrow(oncotree)})"))
