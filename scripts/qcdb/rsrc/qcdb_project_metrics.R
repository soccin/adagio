#
# qcdb_project_metrics.R
#
# Per-sample and per-pair QC metrics of one project, computed the same
# way buildQCDb.R computes them for the background, so the project can
# be compared with a QC database. Column names match the database
# (HSM_, ASM_, ALFRED_, TARGET_, QUALIMAP_, FASTP_, CONPAIR_).
#
# Needs qcdb_readers.R. If buildQCDb.R changes how a metric is computed,
# change it here too.
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
# One row per pair (PAIR = TUMOR__NORMAL): Conpair concordance
#
project_pair_metrics <- function(outDir, pairing, nCores = 1) {
    concordance <- find_qc_files(file.path(outDir, "somatic"), "\\.concordance\\.txt$") |>
        map_qc_files(read_concordance, nCores) |>
        bind_rows()
    if (nrow(concordance) == 0) concordance <- tibble(PAIR = character(), CONPAIR_CONCORDANCE = numeric())
    pairing |>
        select(PAIR, TUMOR_ID, NORMAL_ID) |>
        left_join(concordance, by = "PAIR")
}
