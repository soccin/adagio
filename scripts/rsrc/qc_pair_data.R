#
# qc_pair_data.R
#
# Data for the per-pair QC pages of qcReport02.R (one landscape page per
# tumor/normal pair, modeled on Hartwig's QSee report):
#
#   - pair metrics the project side does not read yet (FACETS, Tempo
#     TMB), read with the readers buildQCDb.R uses
#   - target coverage and insert-size distributions of each sample
#   - % target bases at depths Picard does not report (60x, 250x), from
#     Picard's coverage histogram
#   - the missed-variant likelihood of cancer genes (see gene_mvlh)
#   - sample metadata from meta/*_metadata_samples.csv
#
# Needs qcdb_readers.R and qcdb_project_metrics.R.
#

# Gene lists and gene-to-target maps, built by scripts/qcgenes/buildQCGenes.R
QC_GENES_DIR <- "/data1/core001/work/bic/socci/Resources/QCGenes/v261125"

# Depths for the % target bases rows; those Picard does not report are
# computed from its coverage histogram
PAIR_DEPTHS <- c(10, 20, 30, 60, 100, 250)

# A variant is reliably called with at least this many alt reads
MVLH_MIN_ALT <- 3
# Genes with less of their coding sequence in targets are left out: the
# assay does not capture them, so they would top every sample's list
MVLH_MIN_IN_TARGETS <- 0.5

empty_pair <- function(df) if (nrow(df) == 0) tibble(PAIR = character()) else df

#
# FACETS QC row (purity, LOH, FGA, ...) and Tempo sample_data (TMB) of
# each pair, with the background's column names. Manta SVs are not read:
# exomes have almost none.
#
project_pair_extra <- function(outDir, pairing, nCores = 1) {
    somDir <- file.path(outDir, "somatic")
    facets <- find_qc_files(somDir, "/facets/[^/]+/[^/]+\\.facets_qc\\.txt$") |>
        map_qc_files(read_facets_qc, nCores) |>
        bind_rows() |>
        convert_facets_qc() |>
        rename_with(\(x) str_c("FACETS_", x), -PAIR) |>
        empty_pair()
    sampleData <- find_qc_files(somDir, "\\.sample_data\\.txt$") |>
        map_qc_files(read_sample_data, nCores) |>
        bind_rows() |>
        empty_pair()
    pairing |>
        select(PAIR) |>
        left_join(facets, by = "PAIR") |>
        left_join(sampleData, by = "PAIR")
}

#
# % of target bases at each depth or more, from Picard's high-quality
# coverage histogram (the counts Picard's PCT_TARGET_BASES_NX use):
# SAMPLE, METRIC (HSM_PCT_TARGET_BASES_<N>X), VALUE
#
target_depth_metrics <- function(hist, depths = PAIR_DEPTHS) {
    hist |>
        reframe(
            METRIC = glue("HSM_PCT_TARGET_BASES_{depths}X"),
            VALUE = map_dbl(depths, \(d) sum(HQ_COVERAGE_COUNT[COVERAGE >= d]) / sum(HQ_COVERAGE_COUNT)),
            .by = SAMPLE
        ) |>
        mutate(METRIC = as.character(METRIC))
}

#
# Per-sample distributions for the plots: Picard's target coverage
# histogram and Alfred's insert sizes; and, for the missed-variant
# likelihood, the Alfred coverage of the targets of the genes in
# geneTargets, with the length-weighted mean coverage of all targets.
# Only the genes' targets are kept, so large projects fit in memory.
#
pair_distributions <- function(outDir, samples, geneTargets, hsmDir = file.path(outDir, "post", "qc"),
                               nCores = 1) {
    hsmFiles <- find_qc_files(hsmDir, "\\.hs_metrics\\.txt$")
    hsmFiles <- hsmFiles[sample_from_path(hsmFiles, "\\.hs_metrics\\.txt$") %in% samples]
    coverage <- hsmFiles |>
        map_qc_files(\(f) read_hs_metrics(f)$hist, nCores) |>
        bind_rows()

    alfredFiles <- find_qc_files(file.path(outDir, "bams"), "/alfred/[^/]+\\.alfred\\.tsv\\.gz$")
    alfredFiles <- alfredFiles[sample_from_path(alfredFiles, "\\.alfred\\.tsv\\.gz$") %in% samples]
    geneTargetIds <- unique(geneTargets$TARGET)
    alfred <- alfredFiles |>
        map_qc_files(\(f) {
            a <- read_alfred(f)
            # The target BED lists some targets twice; count each once
            tc <- tibble(TARGET = a$targetCov$id, COV = a$targetCov$cov) |>
                distinct(TARGET, .keep_all = TRUE) |>
                mutate(LENGTH = as.numeric(str_extract(TARGET, "\\d+$")) -
                           as.numeric(str_extract(TARGET, "(?<=:)\\d+")))
            list(
                insertSize = a$insertSize,
                targetMean = tibble(SAMPLE = a$metrics$SAMPLE[1],
                                    ALFRED_TARGET_MEAN = sum(tc$COV * tc$LENGTH) / sum(tc$LENGTH)),
                geneCov = tc |>
                    filter(TARGET %in% geneTargetIds) |>
                    select(TARGET, COV) |>
                    mutate(SAMPLE = a$metrics$SAMPLE[1], .before = 1)
            )
        }, nCores)
    list(
        coverage = coverage,
        insertSize = map(alfred, "insertSize") |> bind_rows(),
        targetMean = map(alfred, "targetMean") |> bind_rows(),
        geneCov = map(alfred, "geneCov") |> bind_rows()
    )
}

#
# Gene resources (see scripts/qcgenes/README.md): genes and their lists,
# gene to target map, IntOGen drivers by cancer type, OncoTree
#
read_gene_resources <- function(dir, assay) {
    files <- c(genes = glue("genes_{assay}.tsv"), targets = glue("gene_targets_{assay}.tsv.gz"),
               intogen = "intogen_drivers.tsv", oncotree = "oncotree.tsv")
    paths <- file.path(dir, files)
    if (!all(fs::file_exists(paths))) {
        stop(glue("Missing gene resources in {dir}: {str_c(files[!fs::file_exists(paths)], collapse = ', ')}"),
             call. = FALSE)
    }
    read <- \(p) read_tsv(p, show_col_types = FALSE, progress = FALSE)
    list(
        dir = dir,
        genes = read(paths[1]),
        targets = read(paths[2]),
        intogen = read(paths[3]),
        oncotree = read(paths[4])
    )
}

# An OncoTree code with its ancestors and descendants (READ: READ,
# COADREAD, BOWEL); none for NA or an unknown code
oncotree_family <- function(code, oncotree) {
    if (is.na(code) || !code %in% oncotree$CODE) return(character())
    parent <- deframe(oncotree |> select(CODE, PARENT))
    up <- code
    while (!is.na(parent[[tail(up, 1)]]) && parent[[tail(up, 1)]] %in% oncotree$CODE) {
        up <- c(up, parent[[tail(up, 1)]])
    }
    down <- code
    repeat {
        more <- oncotree |>
            filter(PARENT %in% down, !CODE %in% down) |>
            pull(CODE)
        if (len(more) == 0) break
        down <- c(down, more)
    }
    unique(c(up, down))
}

#
# Missed-variant likelihood (MVLH, as in Hartwig's QSee): the chance that
# a clonal variant on one allele of a gene has fewer than MVLH_MIN_ALT
# alt reads, averaged over the gene's coding bases.
#
#   VAF at a base = purity / alleles (alleles 1 on X and Y in a male,
#   else 2; the normal has purity 1)
#   MVLH = sum over bases of P(alt reads < MVLH_MIN_ALT | depth, VAF) /
#          number of bases
#
# Depth: each target's mean Alfred coverage, for every coding base in
# it, rescaled so the sample's length-weighted mean over all targets
# equals Picard's mean target coverage (Alfred counts duplicates and
# low-quality reads; Picard does not). Coding bases outside every
# target count with depth 0 when uncaptured is "zero"; with "drop" they
# are left out. Using the target mean ignores depth changes inside a
# target, so the MVLH is lower than a per-base calculation would give.
#
# geneCov: TARGET, COV of one sample. genes: GENE, CHROM, CDS_BASES,
# CDS_BASES_IN_TARGETS. Returns GENE, CHROM, MVLH, MEAN_DEPTH,
# FRAC_IN_TARGETS.
#
gene_mvlh <- function(geneCov, geneTargets, genes, purity, male, scale, uncaptured = c("zero", "drop")) {
    uncaptured <- match.arg(uncaptured)
    if (is.na(purity) || purity <= 0) return(NULL)
    genes <- genes |>
        filter(!is.na(CDS_BASES), CDS_BASES_IN_TARGETS >= MVLH_MIN_IN_TARGETS * CDS_BASES, male | CHROM != "Y") |>
        mutate(ALLELES = if_else(male & CHROM %in% c("X", "Y"), 1, 2), VAF = pmin(1, purity / ALLELES))
    covered <- geneTargets |>
        inner_join(genes |> select(GENE, VAF), by = "GENE") |>
        inner_join(geneCov, by = "TARGET") |>
        mutate(DEPTH = round(COV * scale)) |>
        select(GENE, BASES, DEPTH, VAF)
    outside <- genes |>
        transmute(GENE, BASES = CDS_BASES - CDS_BASES_IN_TARGETS, DEPTH = 0, VAF) |>
        filter(BASES > 0, uncaptured == "zero")
    bind_rows(covered, outside) |>
        mutate(P_MISS = pbinom(MVLH_MIN_ALT - 1, DEPTH, VAF)) |>
        summarize(
            MVLH = sum(BASES * P_MISS) / sum(BASES),
            MEAN_DEPTH = sum(BASES * DEPTH) / sum(BASES),
            .by = GENE
        ) |>
        left_join(genes |> transmute(GENE, CHROM, FRAC_IN_TARGETS = CDS_BASES_IN_TARGETS / CDS_BASES), by = "GENE")
}

#
# Sample metadata from meta/*_metadata_samples.csv: SAMPLE plus the
# columns the pair page shows; empty when there is no such file
#
META_COLUMNS <- c("cmoPatientId", "oncoTreeCode", "preservation", "sampleOrigin", "specimenType",
                  "tissueLocation", "sex")

read_sample_meta <- function(metaDir = "meta") {
    empty <- tibble(SAMPLE = character())
    if (!fs::dir_exists(metaDir)) return(empty)
    files <- fs::dir_ls(metaDir, regexp = "_metadata_samples\\.csv$")
    if (len(files) == 0) return(empty)
    meta <- files |>
        map(\(f) read_csv(f, col_types = cols(.default = "c"), show_col_types = FALSE, progress = FALSE)) |>
        list_rbind()
    idCol <- intersect(c("sampleName", "investigatorSampleId"), names(meta))
    if (len(idCol) == 0) return(empty)
    meta |>
        transmute(SAMPLE = .data[[idCol[1]]], across(any_of(META_COLUMNS))) |>
        filter(!is.na(SAMPLE)) |>
        distinct(SAMPLE, .keep_all = TRUE)
}
