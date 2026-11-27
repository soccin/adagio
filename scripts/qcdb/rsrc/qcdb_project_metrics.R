#
# qcdb_project_metrics.R
#
# Per-sample and per-pair QC metrics of one project, computed the same
# way buildQCDb.R computes them for the background, so the project can
# be compared with a QC database. Column names match the database
# (HSM_, ASM_, ALFRED_, TARGET_, QUALIMAP_, FASTP_, CONPAIR_, TEMPO_,
# FACETS_, MANTA_), and project_sample_dists() and project_gene_mvlh()
# return tables shaped like the database's dist tables.
#
# Needs qcdb_readers.R; project_gene_mvlh() also needs
# scripts/rsrc/qc_pair_data.R. If buildQCDb.R changes how a metric is
# computed, change it here too.
#

#
# Parallel map that stops on the first file that fails to parse
#
map_qc_files <- function(files, fn, nCores = 1) {
    res <- parallel::mclapply(files, \(f) tryCatch(fn(f), error = \(e) e), mc.cores = nCores)
    failed <- map_lgl(res, \(x) inherits(x, c("error", "try-error")))
    if (any(failed)) {
        stop(glue("Cannot parse {files[failed][1]}: {conditionMessage(res[failed][[1]])}"), call. = FALSE)
    }
    res
}

find_qc_files <- function(root, re) {
    if (!fs::dir_exists(root)) return(character())
    fs::dir_ls(root, recurse = TRUE, regexp = re, type = "file") |> as.character()
}

#
# Per-sample target coverage uniformity, as in buildQCDb.R: coverage of
# each target normalized to the sample's median target coverage
#
target_sample_metrics <- function(targetCov, sample) {
    cov <- targetCov$cov
    norm <- cov / median(cov, na.rm = TRUE)
    tibble(
        SAMPLE = sample,
        TARGET_MEDIAN_COV = median(cov, na.rm = TRUE),
        TARGET_FRAC_NORM_COV_LT_0.2 = mean(norm < 0.2, na.rm = TRUE),
        TARGET_FRAC_NORM_COV_GT_2 = mean(norm > 2, na.rm = TRUE),
        TARGET_IQR_NORM_COV = IQR(norm, na.rm = TRUE),
        TARGET_FRAC_ZERO_COV = mean(cov == 0, na.rm = TRUE)
    )
}

#
# One row per sample in sampleMap (SAMPLE, TYPE), one column per metric.
# HsMetrics (COVERAGE_CAP 1000) come from hsmDir and
# AlignmentSummaryMetrics (PAIR row) from asmDir, both post/qc, written
# by scripts/picardqc/doPicardQC.sh; the rest from Tempo's bams and
# somatic folders.
#
project_sample_metrics <- function(outDir, sampleMap, hsmDir = file.path(outDir, "post", "qc"),
                                   asmDir = file.path(outDir, "post", "qc"), nCores = 1) {
    bamDir <- file.path(outDir, "bams")
    somDir <- file.path(outDir, "somatic")

    hsmFiles <- find_qc_files(hsmDir, "\\.hs_metrics\\.txt$")
    if (len(hsmFiles) == 0) {
        stop(glue("No .hs_metrics.txt files in {hsmDir}; run scripts/picardqc/doPicardQC.sh first"),
             call. = FALSE)
    }
    hsm <- hsmFiles |>
        map_qc_files(read_hs_metrics, nCores) |>
        map("metrics") |>
        bind_rows() |>
        rename_with(\(x) str_c("HSM_", x), -SAMPLE)

    asmFiles <- find_qc_files(asmDir, "\\.asm\\.txt$")
    if (len(asmFiles) == 0) {
        stop(glue("No .asm.txt files in {asmDir}; run scripts/picardqc/doPicardQC.sh first (-t asm)"),
             call. = FALSE)
    }
    asm <- asmFiles |>
        map_qc_files(read_asm, nCores) |>
        map("metrics") |>
        bind_rows() |>
        rename_with(\(x) str_c("ASM_", x), -SAMPLE)

    # Keep only the parts of the Alfred file that are used, so the
    # per-target vectors of every sample are not held at once
    alfred <- find_qc_files(bamDir, "/alfred/[^/]+\\.alfred\\.tsv\\.gz$") |>
        map_qc_files(\(f) {
            a <- read_alfred(f)
            sample <- a$metrics$SAMPLE[1]
            list(
                metrics = a$metrics,
                chromMap = a$chromMap,
                onTarget = a$onTarget,
                target = target_sample_metrics(a$targetCov, sample)
            )
        }, nCores)

    alfredMetrics <- alfred |>
        map("metrics") |>
        bind_rows() |>
        rename_with(\(x) str_c("ALFRED_", str_to_upper(x)), -SAMPLE)
    sexMetrics <- alfred |>
        map("chromMap") |>
        bind_rows() |>
        filter(Chrom %in% c("X", "Y", "chrX", "chrY")) |>
        mutate(Chrom = str_remove(Chrom, "^chr")) |>
        select(SAMPLE, Chrom, ObsExpRatio) |>
        pivot_wider(names_from = Chrom, values_from = ObsExpRatio, names_glue = "ALFRED_CHR{Chrom}_OBS_EXP")
    onTargetMetrics <- alfred |>
        map("onTarget") |>
        bind_rows() |>
        filter(Extension %in% c(0, 250)) |>
        pivot_wider(names_from = Extension, values_from = OnTarget, names_glue = "ALFRED_ON_TARGET_EXT{Extension}")
    targetMetrics <- alfred |>
        map("target") |>
        bind_rows()

    qualimapMetrics <- find_qc_files(bamDir, "_qualimap_rawdata\\.tar\\.gz$") |>
        map_qc_files(read_qualimap, nCores) |>
        bind_rows() |>
        rename_with(\(x) str_c("QUALIMAP_", x), -SAMPLE)

    fastpLanes <- find_qc_files(bamDir, "\\.fastp\\.json$") |>
        map_qc_files(read_fastp, nCores) |>
        bind_rows()
    fastpMetrics <- if (nrow(fastpLanes) > 0) summarize_fastp(fastpLanes) else tibble(SAMPLE = character())

    contamination <- find_qc_files(somDir, "\\.contamination\\.txt$") |>
        map_qc_files(read_contamination, nCores) |>
        bind_rows() |>
        select(SAMPLE, CONPAIR_CONTAMINATION) |>
        distinct(SAMPLE, .keep_all = TRUE)

    sampleMap |>
        distinct(SAMPLE, TYPE) |>
        left_join(hsm, by = "SAMPLE") |>
        left_join(asm, by = "SAMPLE") |>
        left_join(alfredMetrics, by = "SAMPLE") |>
        left_join(onTargetMetrics, by = "SAMPLE") |>
        left_join(sexMetrics, by = "SAMPLE") |>
        left_join(targetMetrics, by = "SAMPLE") |>
        left_join(qualimapMetrics, by = "SAMPLE") |>
        left_join(fastpMetrics, by = "SAMPLE") |>
        left_join(contamination, by = "SAMPLE")
}

#
# One row per pair (PAIR = TUMOR__NORMAL), with the columns buildQCDb.R
# puts in pair_metrics: Conpair concordance, Tempo sample_data (TEMPO_
# purity, ploidy, WGD, mutations, TMB), the FACETS QC row (FACETS_), the
# number of HOMDEL genes (FACETS_N_HOMDEL_GENES) and the Manta SV counts
# (MANTA_). Not read: the MAF summaries and the Tempo pair status. A
# source with no files adds no columns, except CONPAIR_CONCORDANCE, which
# is always there.
#
project_pair_metrics <- function(outDir, pairing, nCores = 1) {
    somDir <- file.path(outDir, "somatic")
    read_pairs <- function(re, fn) {
        res <- find_qc_files(somDir, re) |>
            map_qc_files(fn, nCores) |>
            bind_rows()
        if (nrow(res) == 0) tibble(PAIR = character()) else res
    }
    concordance <- read_pairs("\\.concordance\\.txt$", read_concordance)
    if (!"CONPAIR_CONCORDANCE" %in% names(concordance)) {
        concordance <- tibble(PAIR = character(), CONPAIR_CONCORDANCE = numeric())
    }
    sampleData <- read_pairs("\\.sample_data\\.txt$", read_sample_data)
    facets <- find_qc_files(somDir, "/facets/[^/]+/[^/]+\\.facets_qc\\.txt$") |>
        map_qc_files(read_facets_qc, nCores) |>
        bind_rows() |>
        convert_facets_qc() |>
        rename_with(\(x) str_c("FACETS_", x), -PAIR)
    facetsGeneLevel <- read_pairs(FACETS_GENE_LEVEL_RE, read_facets_gene_level)
    manta <- read_pairs("\\.manta\\.vcf\\.gz$", read_manta_count)
    pairing |>
        select(PAIR, TUMOR_ID, NORMAL_ID) |>
        left_join(concordance, by = "PAIR") |>
        left_join(sampleData, by = "PAIR") |>
        left_join(facets, by = "PAIR") |>
        left_join(facetsGeneLevel, by = "PAIR") |>
        left_join(manta, by = "PAIR")
}

#
# Per-sample distributions shaped like the database's dist tables, for
# the given samples:
#   fastp_dup_hist  fastp duplication histogram of each lane
#                   (read_fastp_dup_hist)
#   target_gc_bias  GC-bias curve (target_gc_curve); gcTable is
#                   read_target_gc() of the database's meta$target_gc_file
#
project_sample_dists <- function(outDir, samples, gcTable, nCores = 1) {
    bamDir <- file.path(outDir, "bams")
    fastpFiles <- find_qc_files(bamDir, "\\.fastp\\.json$")
    fastpFiles <- fastpFiles[sample_from_path(fastpFiles, "@.*$") %in% samples]
    alfredFiles <- find_qc_files(bamDir, "/alfred/[^/]+\\.alfred\\.tsv\\.gz$")
    alfredFiles <- alfredFiles[sample_from_path(alfredFiles, "\\.alfred\\.tsv\\.gz$") %in% samples]
    list(
        fastp_dup_hist = fastpFiles |>
            map_qc_files(read_fastp_dup_hist, nCores) |>
            bind_rows(),
        target_gc_bias = alfredFiles |>
            map_qc_files(\(f) {
                a <- read_alfred(f)
                target_gc_curve(a$targetCov$cov, a$targetCov$id, gcTable) |>
                    mutate(SAMPLE = a$metrics$SAMPLE[1], .before = 1)
            }, nCores) |>
            bind_rows()
    )
}

#
# Missed-variant likelihood of each tumor over the OncoKB genes, as
# buildQCDb.R computes dist$gene_mvlh (tumor_gene_mvlh). tumors: one row
# per tumor with SAMPLE, HSM_MEAN_TARGET_COVERAGE, PURITY (FACETS_purity
# of its pair) and MALE (mvlh_male() of the pair's sex call and reported
# sex). genes: read_gene_resources(). Returns SAMPLE plus gene_mvlh()'s
# columns (GENE, MVLH, MEAN_DEPTH, CHROM, FRAC_IN_TARGETS); a tumor with
# no purity has no rows.
#
project_gene_mvlh <- function(outDir, tumors, genes, nCores = 1) {
    alfredFiles <- find_qc_files(file.path(outDir, "bams"), "/alfred/[^/]+\\.alfred\\.tsv\\.gz$")
    alfredFiles <- alfredFiles[sample_from_path(alfredFiles, "\\.alfred\\.tsv\\.gz$") %in% tumors$SAMPLE]
    alfredFiles |>
        map_qc_files(\(f) {
            a <- read_alfred(f)
            s <- a$metrics$SAMPLE[1]
            r <- tumors |> filter(SAMPLE == s)
            m <- tumor_gene_mvlh(a$targetCov$cov, a$targetCov$id, r$HSM_MEAN_TARGET_COVERAGE[1], r$PURITY[1],
                                 r$MALE[1], genes)
            if (is.null(m)) NULL else m |> mutate(SAMPLE = s, .before = 1)
        }, nCores) |>
        bind_rows()
}
