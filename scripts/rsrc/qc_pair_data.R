#
# qc_pair_data.R
#
# Data for the per-pair QC pages of qcReport02.R (one landscape page per
# tumor/normal pair, modeled on Hartwig's QSee report):
#
#   - target coverage and insert-size distributions of each sample
#   - % target bases at depths Picard does not report (60x, 250x), from
#     Picard's coverage histogram
#   - the missed-variant likelihood of cancer genes (see gene_mvlh),
#     which buildQCDb.R also calls for the QC background
#   - the inputs of the project's missed-variant likelihood (mvlh_tumors)
#     and the per-target GC table of the QC database (qcdb_target_gc)
#   - sample metadata from meta/*_metadata_samples.csv
#
# The project's pair metrics (FACETS, Tempo, Manta), duplicate
# histograms, GC-bias curves and missed-variant likelihood come from
# qcdb/rsrc/qcdb_project_metrics.R, which computes them as buildQCDb.R
# does for the background.
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
# histogram and Alfred's insert sizes
#
pair_distributions <- function(outDir, samples, hsmDir = file.path(outDir, "post", "qc"), nCores = 1) {
    hsmFiles <- find_qc_files(hsmDir, "\\.hs_metrics\\.txt$")
    hsmFiles <- hsmFiles[sample_from_path(hsmFiles, "\\.hs_metrics\\.txt$") %in% samples]
    alfredFiles <- find_qc_files(file.path(outDir, "bams"), "/alfred/[^/]+\\.alfred\\.tsv\\.gz$")
    alfredFiles <- alfredFiles[sample_from_path(alfredFiles, "\\.alfred\\.tsv\\.gz$") %in% samples]
    list(
        coverage = hsmFiles |>
            map_qc_files(\(f) read_hs_metrics(f)$hist, nCores) |>
            bind_rows(),
        insertSize = alfredFiles |>
            map_qc_files(\(f) read_alfred(f)$insertSize, nCores) |>
            bind_rows()
    )
}

#
# One row per tumor, the input of project_gene_mvlh(): SAMPLE, PAIR,
# HSM_MEAN_TARGET_COVERAGE, PURITY (the pair's FACETS purity, NA without
# FACETS) and MALE (mvlh_male() of the normal's sex call and the
# reported sex). projSample, projPair: project_sample_metrics() and
# project_pair_metrics(); sexTbl: sex_table() (qc_sex.R).
#
mvlh_tumors <- function(pairing, projSample, projPair, sexTbl) {
    meanCov <- projSample |>
        distinct(SAMPLE, .keep_all = TRUE) |>
        select(SAMPLE, HSM_MEAN_TARGET_COVERAGE)
    purity <- projPair |>
        transmute(PAIR, PURITY = if ("FACETS_purity" %in% names(projPair)) FACETS_purity else NA_real_)
    pairing |>
        transmute(SAMPLE = TUMOR_ID, PAIR) |>
        left_join(meanCov, by = "SAMPLE") |>
        left_join(purity, by = "PAIR") |>
        left_join(sexTbl |> select(PAIR, CALL, REPORTED), by = "PAIR") |>
        mutate(MALE = mvlh_male(CALL, REPORTED)) |>
        select(-CALL, -REPORTED)
}

#
# The per-target GC table the QC database's GC-bias curves were made
# with (meta$target_gc_file), or the file of that name in this adagio's
# assets/qcdb when the path is gone. A database without GC-bias curves
# (versions before 261127) gets an empty table, so target_gc_curve()
# gives no curve.
#
qcdb_target_gc <- function(meta, adagio) {
    file <- meta$target_gc_file
    if (is.null(file)) {
        return(tibble(TARGET = character(), CHROM = character(), START = integer(), END = integer(),
                      LENGTH = integer(), GC = numeric()))
    }
    if (!fs::file_exists(file)) file <- file.path(adagio, "assets", "qcdb", basename(file))
    read_target_gc(file)
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
