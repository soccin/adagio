#
# qcReport02.R
#
# WES QC report against the QC background database (scripts/qcdb). Each
# metric is a panel with the background as one box per type (tumors,
# normals, or pairs) and this project's samples as points over the box
# of their type. Writes two PDFs to post/reports:
#
#   Proj_<no>_qcRpt02_full.pdf     the metrics in rsrc/fullMetrics.txt,
#                                  the concordance and sex page, then
#                                  any other metric with a FAIL
#   Proj_<no>_qcRpt02_summary.pdf  (A) the metrics in rsrc/keyMetrics.txt
#                                  the concordance and sex page
#                                  (B) every other metric with a FAIL
#                                  then a table of every FAIL and WARN
#   Proj_<no>_qcRpt02_flagged.xlsx the same table, with metric IDs and
#                                  unformatted numbers
#
# The concordance and sex page holds the Conpair panels (concordance,
# contamination), ChrY against ChrX (Alfred) for the background and the
# project, and a table with one row per pair: the sex called from the
# normal, the sex reported in meta/*_metadata_samples.csv (when there),
# the tumor checked against its normal, and the Conpair concordance
# (rules in rsrc/qc_sex.R).
#
# A type after a name in keyMetrics.txt (e.g. Tumor for 100X, Normal for
# 20X) limits that metric to the type in the summary report: its panel
# shows only that type, and the other type's flags are dropped from the
# scan and the table. The full report shows every type.
#
# A sample is WARN in a metric when it is beyond the 95th percentile of
# the background of its type on the bad side of the metric, and FAIL
# beyond the 99th (rsrc/metricInfo.tsv: low, high or both; both when not
# listed; both-sided metrics use the central 95% and 99% intervals; see
# rsrc/qc_metric_info.R). Flagged samples get a dark yellow (WARN) or
# dark red (FAIL) ring and a label; short vertical lines in the same
# colors mark the limits on the bad side.
#
# The scan for (B) covers the metrics in rsrc/scanMetrics.txt (Picard,
# ALFRED_DUPLICATEFRACTION, FASTP_AFTER_Q30_RATE and Conpair), minus the
# patterns in rsrc/anomalyExclude.txt, the repeats in
# rsrc/redundantMetrics.txt, the "% Target Bases at NX" metrics that are
# not key metrics, and metrics with no spread in the background. Its
# panels are 30% taller than the others. Pages hold 4 panels (3 on the
# scan pages).
#
# The background is only the samples of the project's sequencer
# technology (NovaSeq 6000 or NovaSeq X, from the instrument ID in the
# fastp file names; qcdb/rsrc/qcdb_seq_tech.R), and only the pairs whose
# tumor and normal both are. Many metrics differ between technologies.
# A project with samples from more than one technology, or from an
# unknown one, or from one with no samples in the background, gets no
# report: the script writes a one-page Proj_<no>_qcRpt02_ERROR.pdf that
# lists every sample and its technology, and stops with an error.
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
source(file.path(SDIR, "qcdb", "rsrc", "qcdb_seq_tech.R"))
source(file.path(SDIR, "rsrc", "read_pairing.R"))
source(file.path(SDIR, "rsrc", "qc_metric_info.R"))
source(file.path(SDIR, "rsrc", "qc_plots.R"))
source(file.path(SDIR, "rsrc", "xlsx_report.R"))
source(file.path(SDIR, "rsrc", "qc_sex.R"))

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

rDir <- "post/reports"
write_pdf <- function(pages, file) {
    fs::dir_create(dirname(file))
    pdf(file, width = 8.5, height = 11)
    walk(pages, print)
    invisible(dev.off())
    message(glue("Wrote {file} ({len(pages)} pages)"))
}

#
# Sequencer technology of each project sample. The project must be on
# one known technology that the background has; if not, write a
# one-page error PDF and stop.
#
techTable <- sampleMap |>
    distinct(SAMPLE, TYPE) |>
    left_join(
        find_qc_files(file.path(outDir, "bams"), "\\.fastp\\.json$") |>
            fastp_lane_tags() |>
            sample_seq_tech(),
        by = "SAMPLE"
    ) |>
    mutate(
        SEQ_TECH = coalesce(SEQ_TECH, "Unknown"),
        INSTRUMENT = coalesce(INSTRUMENT, "no fastp files")
    ) |>
    arrange(SEQ_TECH, TYPE, SAMPLE)
techCounts <- techTable |> count(SEQ_TECH, sort = TRUE)
techSummary <- str_c(glue("{techCounts$SEQ_TECH}: {techCounts$n} samples"), collapse = "; ")
message(glue("Sequencer technology: {techSummary}"))

tech_error <- function(headline, problem) {
    errFile <- file.path(rDir, glue("{projNo}_qcRpt02_ERROR.pdf"))
    page <- fit_table_page(
        glue("{projNo} QC report: {headline}"),
        str_c(
            problem,
            "The report compares a project only with QC background samples of its own sequencer technology.",
            glue("Technology from the instrument ID in the fastp file names: {seq_tech_rules()}; other IDs: Unknown;"),
            "Mixed: one sample with lanes from more than one technology.",
            glue("Samples by technology: {techSummary}."),
            sep = "\n"
        ),
        techTable |> select(Sample = SAMPLE, Type = TYPE, Instrument = INSTRUMENT, Technology = SEQ_TECH)
    )
    write_pdf(list(page), errFile)
    stop(glue("{problem} See {errFile}"), call. = FALSE)
}

techs <- unique(techTable$SEQ_TECH)
if (len(techs) > 1 || identical(techs, "Mixed")) {
    tech_error("mixed sequencer technologies",
               "Mixed technology sets cannot be processed together for the report.")
}
if (identical(techs, "Unknown")) {
    tech_error("unknown sequencer technology",
               "The sequencer technology of these samples is unknown, so there is no QC background to compare with.")
}
seqTech <- techs

#
# Background: the samples of the project's technology, and the pairs
# whose tumor and normal both are
#
bgSamples <- qcdb$samples |>
    distinct(SAMPLE, TYPE) |>
    semi_join(sample_seq_tech(qcdb$dist$fastp_lanes) |> filter(SEQ_TECH == seqTech), by = "SAMPLE")
bgPairs <- qcdb$pairs |>
    filter(TUMOR_ID %in% bgSamples$SAMPLE, NORMAL_ID %in% bgSamples$SAMPLE)
nBgTumor <- sum(bgSamples$TYPE == "Tumor")
nBgNormal <- sum(bgSamples$TYPE == "Normal")
message(glue("QC background, {seqTech} only: {nBgTumor} tumors, {nBgNormal} normals, {nrow(bgPairs)} pairs ",
             "(of {n_distinct(qcdb$samples$SAMPLE)} samples, {nrow(qcdb$pairs)} pairs)"))
if (nBgTumor == 0 || nBgNormal == 0) {
    tech_error(glue("no {seqTech} background"),
               glue("QC background version {qcdb$meta$version} has no {seqTech} tumors or no {seqTech} normals."))
}

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
        filter(SAMPLE %in% bgSamples$SAMPLE) |>
        select(SAMPLE, TYPE, METRIC, VALUE) |>
        add_derived_metrics(c("SAMPLE", "TYPE")) |>
        select(TYPE, METRIC, VALUE),
    qcdb$pair_metrics_long |>
        filter(PAIR %in% bgPairs$PAIR) |>
        select(TYPE, METRIC, VALUE)
) |>
    filter(is.finite(VALUE))

# Metrics not used at all (rsrc/discardMetrics.txt), e.g. bait-based
# HsMetrics
discardRe <- read_metric_list(file.path(SDIR, "rsrc", "discardMetrics.txt")) |>
    str_c(collapse = "|")
bgLong <- bgLong |> filter(!str_detect(METRIC, regex(discardRe)))
projLong <- projLong |> filter(!str_detect(METRIC, regex(discardRe)))

#
# Units, display names and bad sides; background WARN and FAIL
# percentiles by type; flag level, percentile and ranking z of each
# project value
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
keySpec <- read_typed_metric_list(keyFile)
keyMetrics <- keySpec$METRIC |> check_metrics(keyFile)

# Key metrics limited to one type: the (METRIC, TYPE) rows of the other
# types, left out of the key pages and the scan
keyDrop <- bgLong |>
    distinct(METRIC, TYPE) |>
    inner_join(keySpec |> filter(!is.na(TYPE)) |> rename(ONLY = TYPE), by = "METRIC") |>
    filter(TYPE != ONLY) |>
    select(METRIC, TYPE)
keyInfo <- info |>
    left_join(keySpec |> select(METRIC, ONLY = TYPE), by = "METRIC") |>
    mutate(LABEL = if_else(is.na(ONLY), LABEL, str_c(LABEL, " (", str_to_lower(ONLY), "s only)"))) |>
    select(-ONLY)

# The Conpair metrics are drawn on the concordance and sex page, not with
# the other key or full-report metrics
CONCORD_METRICS <- intersect(c("CONPAIR_CONCORDANCE", "CONPAIR_CONTAMINATION"), bgLong$METRIC)

#
# Scan for flagged samples (WARN or FAIL). Scanned: the metrics in
# rsrc/scanMetrics.txt (Picard, ALFRED_DUPLICATEFRACTION,
# FASTP_AFTER_Q30_RATE, Conpair), minus rsrc/anomalyExclude.txt, the
# repeats in rsrc/redundantMetrics.txt (see the notes there), and the
# "% Target Bases at NX" metrics other than the key ones (20X, 100X):
# the key pages already show coverage. Key metrics are always scanned,
# except for the types they are not limited to (normals at 100X, tumors
# at 20X).
#
matches_any <- function(x, file, extra = character()) {
    patterns <- c(read_metric_list(file), extra)
    if (len(patterns) == 0) return(rep(FALSE, len(x)))
    str_detect(x, regex(str_c(patterns, collapse = "|")))
}
scanned <- tibble(METRIC = unique(projLong$METRIC)) |>
    filter(
        METRIC %in% keyMetrics |
            (matches_any(METRIC, file.path(SDIR, "rsrc", "scanMetrics.txt")) &
                 !matches_any(METRIC, file.path(SDIR, "rsrc", "anomalyExclude.txt"), "^HSM_PCT_TARGET_BASES_\\d+X$") &
                 !matches_any(METRIC, file.path(SDIR, "rsrc", "redundantMetrics.txt")))
    ) |>
    pull(METRIC)
message(glue("Scanned metrics: {len(scanned)}"))
hits <- projLong |>
    filter(TYPE != "Pair" | METRIC == "CONPAIR_CONCORDANCE") |>
    anti_join(keyDrop, by = c("METRIC", "TYPE")) |>
    filter(IS_BAD, METRIC %in% scanned) |>
    arrange(LEVEL != "FAIL", desc(abs(Z)))
# Metrics with a FAIL get pages; a WARN alone is only in the table
failMetrics <- hits |>
    filter(LEVEL == "FAIL") |>
    summarize(MAX_ABS_Z = max(abs(Z)), .by = METRIC) |>
    arrange(desc(MAX_ABS_Z)) |>
    pull(METRIC)
scanMetrics <- setdiff(failMetrics, c(keyMetrics, CONCORD_METRICS))

nFail <- sum(hits$LEVEL == "FAIL")
nWarn <- sum(hits$LEVEL == "WARN")
message(glue("Flagged: {nFail} FAIL and {nWarn} WARN cases in {n_distinct(hits$METRIC)} metrics; ",
             "{len(failMetrics)} metrics with a FAIL"))
if (nrow(hits) > 0) {
    hits |>
        select(SAMPLE, TYPE, LEVEL, METRIC, VALUE, MEDIAN, LIMIT, PCTILE, Z) |>
        print(n = Inf, width = 200)
}

#
# Pages
#
meta <- qcdb$meta
nProj <- n_distinct(sampleMap$SAMPLE)
subtitle <- str_c(
    glue("Boxes: QC background {meta$assay} version {meta$version}, {seqTech} samples only: {nBgTumor} tumors, ",
         "{nBgNormal} normals and {nrow(bgPairs)} pairs;"),
    glue("whiskers 1.5 IQR, outliers not shown. Circles: the {nProj} samples of {projectId} ({seqTech})."),
    glue("Rings: dark yellow WARN, beyond the {pct_label(WARN_PCT)} percentile of the background of the same type ",
         "on the bad side;"),
    glue("dark red FAIL, beyond the {pct_label(FAIL_PCT)} (labeled, up to {N_LABEL} per panel, FAIL first)."),
    sep = "\n"
)
caption <- str_c(
    glue("Short vertical lines: the WARN ({pct_label(WARN_PCT)} percentile, dark yellow) and FAIL ",
         "({pct_label(FAIL_PCT)}, dark red) limits of the background of the same type"),
    glue("(tumor, normal or pair), on the bad side only. Metrics bad on both sides: the central ",
         "{100 * WARN_PCT}% and {100 * FAIL_PCT}% intervals."),
    sep = "\n"
)

#
# Sex check (rsrc/qc_sex.R): ChrX and ChrY of the project and of the
# background, reported sex from meta/, one row per pair
#
projXY <- sex_xy(projSample)
bgXY <- qcdb$sample_metrics_long |>
    filter(SAMPLE %in% bgSamples$SAMPLE, METRIC %in% SEX_METRICS) |>
    select(SAMPLE, TYPE, METRIC, VALUE) |>
    pivot_wider(names_from = METRIC, values_from = VALUE) |>
    sex_xy()
reported <- read_reported_sex("meta")
concord <- projLong |>
    filter(METRIC == "CONPAIR_CONCORDANCE") |>
    select(PAIR = SAMPLE, CONCORDANCE = VALUE, CONCORD_LEVEL = LEVEL, SCALE_BY)
sexTbl <- sex_table(projXY, pairing, reported, concord)
message(glue("Sex: reported sex for {sum(!is.na(sexTbl$REPORTED))} of {nrow(sexTbl)} pairs; ",
             "{sum(sexTbl$STATUS != 'OK')} pairs with a problem"))
print(sexTbl, width = 200)
sexDisplay <- sexTbl |>
    transmute(
        Tumor = TUMOR_ID,
        Normal = NORMAL_ID,
        Reported = coalesce(REPORTED, "-"),
        Called = CALL,
        `ChrX N` = sprintf("%.2f", XN),
        `ChrY N` = sprintf("%.3f", YN),
        `ChrX T` = sprintf("%.2f", XT),
        `ChrY T` = sprintf("%.3f", YT),
        Concordance = if_else(is.na(CONCORDANCE), "-",
                              str_c(sprintf("%.1f%%", 100 * CONCORDANCE / SCALE_BY), coalesce(str_c(" ", CONCORD_LEVEL), ""))),
        Status = STATUS
    )
sexLabels <- sexTbl |>
    filter(STATUS != "OK") |>
    select(TUMOR_ID, NORMAL_ID) |>
    unlist() |>
    head(2 * N_LABEL)
concord_section <- function(title) {
    concordance_pages(
        CONCORD_METRICS, info, bgLong, projLong, limLong,
        \(fillTypes) sex_plot(bgXY, projXY, sexLabels, fillTypes),
        sexDisplay, sex_rules_text(),
        title, subtitle,
        str_c(caption, "Sex table: N normal, T tumor; ChrX and ChrY reads, observed/expected (Alfred).",
              sep = "\n")
    )
}

# Full report: the fixed list, the concordance and sex page, then the
# scan metrics with a FAIL that the list does not already show
fullPages <- c(
    qc_pages(setdiff(fullMetrics, CONCORD_METRICS), info, bgLong, projLong, limLong, glue("{projNo} QC report"),
             subtitle, caption),
    concord_section(glue("{projNo} QC report: concordance and sex")),
    qc_pages(
        setdiff(scanMetrics, fullMetrics), info, bgLong, projLong, limLong,
        glue("{projNo} QC report: other metrics with a FAIL"),
        subtitle, caption,
        panelHeight = 1.3
    )
)

keyPages <- qc_pages(
    setdiff(keyMetrics, CONCORD_METRICS), keyInfo,
    bgLong |> anti_join(keyDrop, by = c("METRIC", "TYPE")),
    projLong |> anti_join(keyDrop, by = c("METRIC", "TYPE")),
    limLong |> anti_join(keyDrop, by = c("METRIC", "TYPE")),
    glue("{projNo} QC summary: key metrics"),
    subtitle, caption
)
scanPages <- qc_pages(
    scanMetrics, info, bgLong, projLong, limLong,
    glue("{projNo} QC summary: other metrics with a FAIL"),
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
        Level = LEVEL,
        Metric = if_else(METRIC %in% keyMetrics, str_c(METRIC_LABEL, " *"), METRIC_LABEL),
        Value = format_value(VALUE, KIND, SCALE_BY),
        Median = format_value(MEDIAN, KIND, SCALE_BY),
        Limit = format_value(LIMIT, KIND, SCALE_BY),
        Percentile = sprintf("%.1f%%", 100 * PCTILE)
    )
#
# The same table as Excel, for review: metric IDs, and numbers in
# display units (percentages as percent; see Unit), not rounded
#
unit_of <- function(kind) {
    case_when(kind %in% PERCENT_KINDS ~ "%", kind == "cov" ~ "x", kind == "bp" ~ "bp", .default = NA_character_)
}
to_display <- function(x, kind, scaleBy) if_else(kind %in% PERCENT_KINDS, 100 * x / scaleBy, x)
hitXlsx <- hits |>
    left_join(info |> select(METRIC, KIND, METRIC_LABEL = LABEL), by = "METRIC") |>
    transmute(
        Sample = if_else(TYPE == "Pair", LABEL, SAMPLE),
        Type = TYPE,
        Level = LEVEL,
        Metric = METRIC_LABEL,
        `Metric ID` = METRIC,
        Key = if_else(METRIC %in% keyMetrics, "yes", NA_character_),
        Value = to_display(VALUE, KIND, SCALE_BY),
        Median = to_display(MEDIAN, KIND, SCALE_BY),
        Limit = to_display(LIMIT, KIND, SCALE_BY),
        Unit = unit_of(KIND),
        Percentile = round(100 * PCTILE, 1),
        `Bad side` = BAD,
        `Robust z` = round(Z, 2)
    )
xlsxFile <- file.path(rDir, glue("{projNo}_qcRpt02_flagged.xlsx"))
fs::dir_create(rDir)
wb <-openxlsx2::wb_workbook() |>
    add_report_sheet("Flagged", hitXlsx) |>
    openxlsx2::wb_add_filter(rows = 1, cols = seq_along(hitXlsx))
if (nrow(hitXlsx) > 0) {
    # add_report_sheet gives these columns two decimals; they mix read
    # counts with small percentages, so General shows each value as is
    wb <- wb |> openxlsx2::wb_add_numfmt(
        dims = openxlsx2::wb_dims(rows = 1 + seq_len(nrow(hitXlsx)),
                                  cols = which(names(hitXlsx) %in% c("Value", "Median", "Limit"))),
        numfmt = "General"
    )
}
wb |>
    openxlsx2::wb_set_bookview(
        x_window = XLSX_WINDOW$x, y_window = XLSX_WINDOW$y,
        window_width = XLSX_WINDOW$width, window_height = XLSX_WINDOW$height
    ) |>
    openxlsx2::wb_save(xlsxFile, overwrite = TRUE)
message(glue("Wrote {xlsxFile} ({nrow(hitXlsx)} rows)"))

tableTitle <- glue("{projNo} QC summary: flagged samples")
hitPages <- if (nrow(hits) == 0) {
    list(text_page(
        tableTitle,
        glue("No sample is beyond the {pct_label(WARN_PCT)} percentile of the {seqTech} background of its type\n",
             "on the bad side of any scanned metric.")
    ))
} else {
    table_pages(
        hitTable,
        tableTitle,
        str_c(
            glue("{nFail} FAIL and {nWarn} WARN cases in {n_distinct(hits$METRIC)} metrics, FAIL first. ",
                 "FAIL: beyond the {pct_label(FAIL_PCT)} percentile of the background"),
            glue("of the same type on the bad side; WARN: beyond the {pct_label(WARN_PCT)}. ",
                 "Metrics bad on both sides: the central {100 * WARN_PCT}% and {100 * FAIL_PCT}% intervals."),
            glue("Background: the {seqTech} samples of QC background version {meta$version}. ",
                 "Median: background median. Limit: the limit crossed."),
            "Percentile: percent of the background of the same type at or below the value. *: a key metric.",
            sep = "\n"
        )
    )
}

write_pdf(fullPages, file.path(rDir, glue("{projNo}_qcRpt02_full.pdf")))
concordPages <- concord_section(glue("{projNo} QC summary: concordance and sex"))
write_pdf(c(keyPages, concordPages, scanPages, hitPages), file.path(rDir, glue("{projNo}_qcRpt02_summary.pdf")))
