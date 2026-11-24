#
# qcReport02.R
#
# WES QC report against the QC background database (scripts/qcdb). Each
# metric is a panel with the background as one box per type (tumors,
# normals, or pairs) and this project's samples as points over the box
# of their type. Writes two PDFs to post/reports:
#
#   Proj_<no>_qcRpt02_full.pdf     the metrics in rsrc/fullMetrics.txt,
#                                  then any other metric with a bad
#                                  sample
#   Proj_<no>_qcRpt02_summary.pdf  (A) the metrics in rsrc/keyMetrics.txt
#                                  (B) every other metric with a bad
#                                      sample
#                                  then a table of every bad sample
#
# A sample is bad in a metric when it is more than 3 robust SD from the
# background median of its type on the bad side of the metric
# (rsrc/metricInfo.tsv: low, high or both; both when not listed). Robust
# SD = 1.2533 x the mean absolute deviation from the median. Percentages
# are judged in log-odds space (rsrc/qc_metric_info.R). Only bad samples
# are ringed and labeled; short vertical lines mark the limits on the
# bad side.
#
# The scan for (B) covers the numeric per-sample metrics of the database
# and Conpair concordance, minus the patterns in rsrc/anomalyExclude.txt
# and metrics with no spread in the background. Its panels are 30%
# taller than the others.
#
# Run from the project folder (the one that holds out/) after
# scripts/picardqc/doPicardQC.sh (uncapped HsMetrics and
# AlignmentSummaryMetrics). It reads every Alfred and Qualimap file of
# the project, so submit large projects with sbatch.
#

usage <- function() {
    cat("
Usage: Rscript qcReport02.R [options]

WES QC report: project samples against the QC background database.

Options:
  --qcdb=FILE     QC database .rds (default: newest for the assay in
                  assets/qcdb/qcdb_index.tsv)
  --version=V     QC database version (yymmdd) from the index
  --cores=N       parallel workers (default: SLURM_CPUS_PER_TASK or 1)
  -h, --help      show this help
")
}

args <- commandArgs(trailingOnly = TRUE)
if (any(args %in% c("-h", "--help"))) {
    usage()
    quit(status = 0)
}

bad <- args[!grepl("^--[A-Za-z-]+=", args)]
if (length(bad) > 0) {
    usage()
    stop("Unknown argument(s): ", paste(bad, collapse = " "), call. = FALSE)
}
opt <- as.list(setNames(sub("^--[A-Za-z-]+=", "", args), sub("^--([A-Za-z-]+)=.*", "\\1", args)))

suppressPackageStartupMessages({
    library(tidyverse)
    library(glue)
})

SDIR <- get_script_dir()
ADAGIO <- normalizePath(file.path(SDIR, ".."))
source(file.path(SDIR, "qcdb", "rsrc", "qcdb_readers.R"))
source(file.path(SDIR, "qcdb", "rsrc", "qcdb_index.R"))
source(file.path(SDIR, "qcdb", "rsrc", "qcdb_project_metrics.R"))
source(file.path(SDIR, "rsrc", "read_pairing.R"))
source(file.path(SDIR, "rsrc", "qc_metric_info.R"))
source(file.path(SDIR, "rsrc", "qc_plots.R"))

nCores <- as.integer(opt$cores %||% Sys.getenv("SLURM_CPUS_PER_TASK", "1"))

# Tempo TARGET (mapping file) to QC database assay label
TARGET_TO_ASSAY <- c(idt_v2 = "WES_IDT_v2")

#
# Locate the run; exomes only
#
outDir <- fs::dir_ls("out", type = "directory") |>
    str_subset("/metrics$", negate = TRUE)
if (len(outDir) != 1) stop("Cannot pick a project folder under ./out", call. = FALSE)
projectId <- basename(outDir)
projNo <- if (str_detect(projectId, "^Proj_")) projectId else str_c("Proj_", projectId)

cmdLog <- read_lines(file.path(outDir, "runlog", "cmd.sh.log"))
assayType <- cmdLog |>
    str_subset("^ASSAY_TYPE:") |>
    str_remove("^ASSAY_TYPE:\\s*")
if (!identical(assayType, "exome")) {
    stop(glue("qcReport02.R is for exomes only; ASSAY_TYPE is {str_c(assayType, collapse = ',')}"), call. = FALSE)
}

mappingFile <- cmdLog |>
    str_c(collapse = " ") |>
    str_extract("--mapping[= ]+(\\S+)", group = 1)
mappingCopy <- file.path(outDir, "runlog", basename(mappingFile))
if (fs::file_exists(mappingCopy)) mappingFile <- mappingCopy
targets <- read_tsv(mappingFile, show_col_types = FALSE, progress = FALSE) |>
    distinct(TARGET) |>
    pull(TARGET)
if (len(targets) != 1) stop(glue("More than one TARGET in {mappingFile}: {str_c(targets, collapse = ', ')}"), call. = FALSE)
if (!targets %in% names(TARGET_TO_ASSAY)) {
    stop(glue("No QC background database for target {targets}"), call. = FALSE)
}
assay <- unname(TARGET_TO_ASSAY[targets])

qcdbFile <- find_qcdb(ADAGIO, assay, opt$version, opt$qcdb)
message(glue("Project: {projectId}\nQC database: {qcdbFile}"))
qcdb <- readRDS(qcdbFile)

#
# Project metrics, computed as the database computes them
#
pairing <- read_pairing("out") |>
    mutate(PAIR = str_c(TUMOR_ID, "__", NORMAL_ID))
sampleMap <- bind_rows(
    pairing |> transmute(SAMPLE = TUMOR_ID, TYPE = "Tumor", PAIR),
    pairing |> transmute(SAMPLE = NORMAL_ID, TYPE = "Normal", PAIR)
)

message("Reading project QC")
projSample <- project_sample_metrics(outDir, sampleMap, nCores = nCores)
projPair <- project_pair_metrics(outDir, pairing, nCores = nCores)

# Derived metrics (e.g. strand balance) replace their source metrics in
# both the project and the background (rsrc/qc_metric_info.R)
projLong <- bind_rows(
    projSample |>
        select(SAMPLE, TYPE, where(is.numeric)) |>
        pivot_longer(-c(SAMPLE, TYPE), names_to = "METRIC", values_to = "VALUE") |>
        mutate(LABEL = SAMPLE) |>
        add_derived_metrics(c("SAMPLE", "TYPE", "LABEL")),
    projPair |>
        select(SAMPLE = PAIR, LABEL = TUMOR_ID, where(is.numeric)) |>
        pivot_longer(-c(SAMPLE, LABEL), names_to = "METRIC", values_to = "VALUE") |>
        mutate(TYPE = "Pair")
)

bgLong <- bind_rows(
    qcdb$sample_metrics_long |>
        select(SAMPLE, TYPE, METRIC, VALUE) |>
        add_derived_metrics(c("SAMPLE", "TYPE")) |>
        select(TYPE, METRIC, VALUE),
    qcdb$pair_metrics_long |> select(TYPE, METRIC, VALUE)
) |>
    filter(is.finite(VALUE))

# Metrics not used at all (rsrc/discardMetrics.txt), e.g. bait-based
# HsMetrics
discardRe <- read_metric_list(file.path(SDIR, "rsrc", "discardMetrics.txt")) |>
    str_c(collapse = "|")
bgLong <- bgLong |> filter(!str_detect(METRIC, regex(discardRe)))
projLong <- projLong |> filter(!str_detect(METRIC, regex(discardRe)))

#
# Units, display names and bad sides; background median and robust SD by type
# (in log-odds for percentages); z and bad flag of each project value
#
info <- metric_info(bgLong, projLong, file.path(SDIR, "rsrc", "metricInfo.tsv"))
stats <- background_stats(bgLong, info)
limLong <- limit_lines(stats)
projLong <- score_project(projLong, stats)

check_metrics <- function(metrics, file) {
    unknown <- setdiff(metrics, bgLong$METRIC)
    if (len(unknown) > 0) {
        message(glue("WARNING: not in the QC database, skipped ({basename(file)}): {str_c(unknown, collapse = ', ')}"))
    }
    intersect(metrics, bgLong$METRIC)
}

fullFile <- file.path(SDIR, "rsrc", "fullMetrics.txt")
keyFile <- file.path(SDIR, "rsrc", "keyMetrics.txt")
fullMetrics <- read_metric_list(fullFile) |> check_metrics(fullFile)
keyMetrics <- read_metric_list(keyFile) |> check_metrics(keyFile)

#
# Scan for bad samples
#
excludeRe <- read_metric_list(file.path(SDIR, "rsrc", "anomalyExclude.txt")) |>
    str_c(collapse = "|")
hits <- projLong |>
    filter(TYPE != "Pair" | METRIC == "CONPAIR_CONCORDANCE") |>
    filter(!str_detect(METRIC, regex(excludeRe)), IS_BAD) |>
    arrange(desc(abs(Z)))
hitMetrics <- hits |>
    summarize(MAX_ABS_Z = max(abs(Z)), .by = METRIC) |>
    arrange(desc(MAX_ABS_Z)) |>
    pull(METRIC)
scanMetrics <- setdiff(hitMetrics, keyMetrics)

message(glue("Bad samples (beyond {Z_FLAG} robust SD on the bad side): {nrow(hits)} cases in {len(hitMetrics)} metrics"))
if (nrow(hits) > 0) {
    hits |>
        select(SAMPLE, TYPE, METRIC, VALUE, MEDIAN, LOW, HIGH, Z) |>
        print(n = Inf, width = 200)
}

#
# Pages
#
meta <- qcdb$meta
nBg <- qcdb$samples |>
    count(TYPE) |>
    deframe()
nProj <- n_distinct(sampleMap$SAMPLE)
subtitle <- str_c(
    glue("Boxes: QC background {meta$assay} version {meta$version}, {nBg[['Tumor']]} tumors and ",
         "{nBg[['Normal']]} normals; whiskers 1.5 IQR, outliers not shown."),
    glue("Circles: the {nProj} samples of {projectId}. Orange rings: more than {Z_FLAG} robust SD from the ",
         "background median of their type"),
    glue("on the bad side (labeled, up to {N_LABEL} per panel)."),
    sep = "\n"
)
caption <- str_c(
    glue("Short vertical lines: median +/- {Z_FLAG} robust SD of the background of the same type ",
         "(tumor, normal or pair), on the bad side only."),
    glue("Robust SD = {MAD_TO_SD} x mean absolute deviation from the median; for percentages, computed in log-odds."),
    sep = "\n"
)

# Full report: the fixed list, then only those scan metrics with a bad
# sample that the list does not already show
fullPages <- c(
    qc_pages(fullMetrics, info, bgLong, projLong, limLong, glue("{projNo} QC report"), subtitle, caption),
    qc_pages(
        setdiff(hitMetrics, fullMetrics), info, bgLong, projLong, limLong,
        glue("{projNo} QC report: other metrics with a bad sample"),
        subtitle, caption,
        panelHeight = 1.3
    )
)

keyPages <- qc_pages(
    keyMetrics, info, bgLong, projLong, limLong,
    glue("{projNo} QC summary: key metrics"),
    subtitle, caption
)
scanPages <- qc_pages(
    scanMetrics, info, bgLong, projLong, limLong,
    glue("{projNo} QC summary: other metrics with a bad sample"),
    subtitle, caption,
    panelHeight = 1.3
)

format_num <- function(x, digits = 4) {
    map_chr(x, \(v) format(signif(v, digits), big.mark = ",", scientific = FALSE, trim = TRUE, drop0trailing = TRUE))
}
# Percentages as percent, everything else as a number
format_value <- function(x, kind, scaleBy) {
    if_else(kind %in% PERCENT_KINDS, str_c(format_num(100 * x / scaleBy, 3), "%"), format_num(x))
}

hitTable <- hits |>
    left_join(info |> select(METRIC, KIND, METRIC_LABEL = LABEL), by = "METRIC") |>
    transmute(
        Sample = if_else(TYPE == "Pair", LABEL, SAMPLE),
        Type = TYPE,
        Metric = METRIC_LABEL,
        Value = format_value(VALUE, KIND, SCALE_BY),
        `Background median` = format_value(MEDIAN, KIND, SCALE_BY),
        Limit = format_value(if_else(Z < 0, LOW, HIGH), KIND, SCALE_BY),
        z = sprintf("%.1f", Z),
        `Key metric` = if_else(METRIC %in% keyMetrics, "yes", "")
    )
tableTitle <- glue("{projNo} QC summary: bad samples")
hitPages <- if (nrow(hits) == 0) {
    list(text_page(
        tableTitle,
        glue("No sample is more than {Z_FLAG} robust SD from the background median of its type on the bad side ",
             "of any scanned metric.")
    ))
} else {
    table_pages(
        hitTable,
        tableTitle,
        str_c(
            glue("{nrow(hits)} cases in {len(hitMetrics)} metrics, largest |z| first: samples more than {Z_FLAG} ",
                 "robust SD from the background median of their type on the bad side."),
            "z = (value - background median) / robust SD, same type; for percentages, computed in log-odds.",
            glue("Robust SD = {MAD_TO_SD} x mean absolute deviation from the median. ",
                 "Limit: median +/- {Z_FLAG} robust SD on the bad side."),
            sep = "\n"
        )
    )
}

rDir <- "post/reports"
fs::dir_create(rDir)
write_pdf <- function(pages, file) {
    pdf(file, width = 8.5, height = 11)
    walk(pages, print)
    invisible(dev.off())
    message(glue("Wrote {file} ({len(pages)} pages)"))
}
write_pdf(fullPages, file.path(rDir, glue("{projNo}_qcRpt02_full.pdf")))
write_pdf(c(keyPages, scanPages, hitPages), file.path(rDir, glue("{projNo}_qcRpt02_summary.pdf")))
