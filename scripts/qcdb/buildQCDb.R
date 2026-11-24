#
# buildQCDb.R
#
# Build a QC background database from the outputs of a finished Tempo
# (adagio) run. The database is one .rds file holding a list of tibbles;
# see README.md in this folder for the layout.
#
# Run from the project folder (the one that holds out/), or pass --out.
# This reads every QC file of every sample, so submit it with
# runBuildQCDb.sh rather than running it on an interactive node.
#

usage <- function() {
    cat("
Usage: Rscript buildQCDb.R [options]

Build the QC background database (.rds) from a finished adagio run.

Options:
  --out=DIR       project output folder, out/<PROJECT_ID>
                  (default: the only project folder under ./out)
  --pairing=FILE  pairing file NORMAL_ID<TAB>TUMOR_ID with header
                  (default: the one recorded in runlog/cmd.sh.log)
  --lims=FILE     optional sample metadata CSV with one row per sample;
                  joined on the column given by --lims-key
  --lims-key=COL  sample ID column in --lims (default: dir_sample_name)
  --hsmetrics=DIR folder of <SAMPLE>.hs_metrics.txt files
                  (default: <out>/post/qc, written by
                  scripts/picardqc/doPicardQC.sh without Tempo's 200x
                  cap; <out>/bams reads Tempo's capped files)
  --asm=DIR       folder of <SAMPLE>.asm.txt files, Picard
                  CollectAlignmentSummaryMetrics (default: <out>/post/qc,
                  written by scripts/picardqc/doPicardQC.sh)
  --assay=LABEL   assay label used in the file name (default: WES_IDT_v2)
  --version=V     version label (default: the build date, yymmdd)
  --dest=DIR      output folder (default: ./qcdb in the project folder)
  --cores=N       parallel workers (default: SLURM_CPUS_PER_TASK or 1)
  -h, --help      show this help

Output: <dest>/qcdb_<assay>_<version>.rds. An existing file is never
overwritten; give a new --version instead.

The .rds is not stored in git. After a build, add the line printed at
the end to <adagio>/assets/qcdb/qcdb_index.tsv so reports can find it.
")
}

args <- commandArgs(trailingOnly = TRUE)
if (any(args %in% c("-h", "--help"))) {
    usage()
    quit(status = 0)
}

parse_args <- function(args) {
    bad <- args[!grepl("^--[A-Za-z-]+=", args)]
    if (length(bad) > 0) {
        usage()
        stop("Unknown argument(s): ", paste(bad, collapse = " "), call. = FALSE)
    }
    keys <- sub("^--([A-Za-z-]+)=.*", "\\1", args)
    vals <- sub("^--[A-Za-z-]+=", "", args)
    as.list(setNames(vals, keys))
}

opt <- parse_args(args)

suppressPackageStartupMessages({
    library(tidyverse)
    library(glue)
})

SDIR <- get_script_dir()
ADAGIO <- normalizePath(file.path(SDIR, "..", ".."))
source(file.path(SDIR, "rsrc", "qcdb_readers.R"))
source(file.path(ADAGIO, "scripts", "rsrc", "read_pairing.R"))

nCores <- as.integer(opt$cores %||% Sys.getenv("SLURM_CPUS_PER_TASK", "1"))
assay <- opt$assay %||% "WES_IDT_v2"
destDir <- opt$dest %||% "qcdb"
limsKey <- opt[["lims-key"]] %||% "dir_sample_name"

# Stop before reading anything if the output exists: a second build on
# the same day would otherwise replace a database already in the index
version <- opt$version %||% format(Sys.Date(), "%y%m%d")
if (!str_detect(version, "^[A-Za-z0-9_.-]+$")) stop(glue("Bad --version: {version}"), call. = FALSE)
outFile <- file.path(destDir, glue("qcdb_{assay}_{version}.rds"))
if (fs::file_exists(outFile)) {
    stop(glue("{outFile} exists; give a new --version"), call. = FALSE)
}

#
# Parallel map over files; the result is a list in input order. A file
# that fails to parse becomes NULL and is reported, so one bad file does
# not stop the build.
#
map_files <- function(files, fn, label) {
    message(glue("  {label}: {len(files)} files"))
    res <- parallel::mclapply(files, \(f) tryCatch(fn(f), error = \(e) e), mc.cores = nCores)
    failed <- map_lgl(res, \(x) inherits(x, "error"))
    if (any(failed)) {
        walk2(files[failed], res[failed], \(f, e) message(glue("    FAILED {f}: {conditionMessage(e)}")))
        failedFiles <<- bind_rows(failedFiles, tibble(READER = label, FILE = files[failed],
                                                      ERROR = map_chr(res[failed], conditionMessage)))
    }
    res[failed] <- list(NULL)
    res
}
failedFiles <- tibble(READER = character(), FILE = character(), ERROR = character())

find_files <- function(root, re) {
    fs::dir_ls(root, recurse = TRUE, regexp = re, type = "file") |> as.character()
}

#
# Locate the run
#
outDir <- opt$out
if (is.null(outDir)) {
    outDir <- fs::dir_ls("out", type = "directory") |>
        str_subset("/metrics$", negate = TRUE)
    if (len(outDir) != 1) stop("Cannot pick a project folder under ./out; use --out", call. = FALSE)
}
outDir <- normalizePath(outDir)
projectId <- basename(outDir)
message(glue("Project: {projectId}\nOutput folder: {outDir}"))

pairing <- if (!is.null(opt$pairing)) {
    read_tsv_quiet(opt$pairing) |> select(NORMAL_ID, TUMOR_ID)
} else {
    read_pairing(dirname(outDir))
}
pairing <- pairing |>
    distinct() |>
    mutate(PAIR = str_c(TUMOR_ID, "__", NORMAL_ID))
message(glue("Pairs in pairing file: {nrow(pairing)}"))

sampleMap <- bind_rows(
    pairing |> transmute(SAMPLE = TUMOR_ID, TYPE = "Tumor", PAIR),
    pairing |> transmute(SAMPLE = NORMAL_ID, TYPE = "Normal", PAIR)
)

if (any(duplicated(sampleMap$SAMPLE))) {
    message("NOTE: some samples are in more than one pair; sample metrics are joined to each pair")
}

bamDir <- file.path(outDir, "bams")
somDir <- file.path(outDir, "somatic")

#
# HsMetrics: by default the files from scripts/picardqc/doPicardQC.sh,
# which reruns Picard without Tempo's COVERAGE_CAP of 200
#
hsmDir <- normalizePath(opt$hsmetrics %||% file.path(outDir, "post", "qc"), mustWork = FALSE)
hsmFiles <- if (fs::dir_exists(hsmDir)) find_files(hsmDir, "\\.hs_metrics\\.txt$") else character()
if (len(hsmFiles) == 0) {
    stop(glue("No .hs_metrics.txt files in {hsmDir}\n",
              "Run scripts/picardqc/doPicardQC.sh first, or use --hsmetrics=<out>/bams ",
              "for Tempo's files (capped at 200x)"), call. = FALSE)
}

#
# Picard CollectAlignmentSummaryMetrics: Tempo does not run it;
# scripts/picardqc/doPicardQC.sh does
#
asmDir <- normalizePath(opt$asm %||% file.path(outDir, "post", "qc"), mustWork = FALSE)
asmFiles <- if (fs::dir_exists(asmDir)) find_files(asmDir, "\\.asm\\.txt$") else character()
if (len(asmFiles) == 0) {
    stop(glue("No .asm.txt files in {asmDir}\n",
              "Run scripts/picardqc/doPicardQC.sh first (-t asm)"), call. = FALSE)
}
message(glue("AlignmentSummaryMetrics: {asmDir}"))
# Picard writes its command line in the header; no COVERAGE_CAP there
# means the default, 200
hsm_cap <- function(file) {
    read_lines(file, n_max = 2) |>
        str_c(collapse = " ") |>
        str_extract("--COVERAGE_CAP (\\d+)", group = 1) |>
        coalesce("200")
}
hsmCap <- hsmFiles |>
    map_chr(hsm_cap) |>
    unique() |>
    as.integer()
if (len(hsmCap) != 1) {
    stop(glue("HsMetrics files in {hsmDir} use different COVERAGE_CAP values: {str_c(hsmCap, collapse = ', ')}"),
         call. = FALSE)
}
message(glue("HsMetrics: {hsmDir} (COVERAGE_CAP {hsmCap})"))

#
# Per-sample QC
#
message("Reading per-sample QC")

hsm <- hsmFiles |> map_files(read_hs_metrics, "hs_metrics")
asm <- asmFiles |> map_files(read_asm, "asm")
alfred <- find_files(bamDir, "/alfred/[^/]+\\.alfred\\.tsv\\.gz$") |> map_files(read_alfred, "alfred")
qualimap <- find_files(bamDir, "_qualimap_rawdata\\.tar\\.gz$") |> map_files(read_qualimap, "qualimap")
fastpLanes <- find_files(bamDir, "\\.fastp\\.json$") |> map_files(read_fastp, "fastp") |> bind_rows()
statusSample <- find_files(bamDir, "/multiqc/[^/]+\\.QC_Status\\.txt$") |>
    map_files(read_tempo_status, "tempo_status_sample") |>
    bind_rows()

pluck_bind <- function(lst, el) lst |> compact() |> map(el) |> bind_rows()

hsmMetrics <- pluck_bind(hsm, "metrics") |> rename_with(\(x) str_c("HSM_", x), -SAMPLE)
asmMetrics <- pluck_bind(asm, "metrics") |> rename_with(\(x) str_c("ASM_", x), -SAMPLE)
alfredMetrics <- pluck_bind(alfred, "metrics") |> rename_with(\(x) str_c("ALFRED_", str_to_upper(x)), -SAMPLE)
qualimapMetrics <- qualimap |> compact() |> bind_rows() |> rename_with(\(x) str_c("QUALIMAP_", x), -SAMPLE)
fastpMetrics <- if (nrow(fastpLanes) > 0) summarize_fastp(fastpLanes) else tibble(SAMPLE = character())

#
# Sex check inputs: observed/expected mapped reads on X and Y (Alfred CM)
#
chromMap <- pluck_bind(alfred, "chromMap")
sexMetrics <- chromMap |>
    filter(Chrom %in% c("X", "Y", "chrX", "chrY")) |>
    mutate(Chrom = str_remove(Chrom, "^chr")) |>
    select(SAMPLE, Chrom, ObsExpRatio) |>
    pivot_wider(names_from = Chrom, values_from = ObsExpRatio, names_glue = "ALFRED_CHR{Chrom}_OBS_EXP")

#
# Alfred on-target fraction with 0 and 250 bp extension
#
onTarget <- pluck_bind(alfred, "onTarget")
onTargetMetrics <- onTarget |>
    filter(Extension %in% c(0, 250)) |>
    pivot_wider(names_from = Extension, values_from = OnTarget, names_glue = "ALFRED_ON_TARGET_EXT{Extension}")

#
# Per-target coverage. Each sample is normalized to its median target
# coverage; the database keeps per-target summaries across normals and
# across tumors (the full matrix is too large to ship).
#
message("Summarizing per-target coverage")
alfredOK <- compact(alfred)
targetSummary <- tibble()
targetSampleMetrics <- tibble(SAMPLE = character())
if (len(alfredOK) > 0) {
    targetIds <- alfredOK[[1]]$targetCov$id
    covMat <- alfredOK |>
        map(\(a) {
            tc <- a$targetCov
            if (identical(tc$id, targetIds)) tc$cov else tc$cov[match(targetIds, tc$id)]
        }) |>
        do.call(what = cbind)
    colnames(covMat) <- map_chr(alfredOK, \(a) a$metrics$SAMPLE[1])
    normMat <- sweep(covMat, 2, matrixStats::colMedians(covMat, na.rm = TRUE), "/")

    sampleType <- sampleMap |> distinct(SAMPLE, TYPE) |> deframe()
    target_stats <- function(type) {
        keep <- unname(sampleType[colnames(covMat)]) == type
        keep[is.na(keep)] <- FALSE
        if (!any(keep)) return(NULL)
        nm <- normMat[, keep, drop = FALSE]
        q <- matrixStats::rowQuantiles(nm, probs = c(0.05, 0.95), na.rm = TRUE, drop = FALSE)
        tibble(
            TARGET = targetIds,
            TYPE = type,
            N_SAMPLES = sum(keep),
            MEDIAN_COV = matrixStats::rowMedians(covMat[, keep, drop = FALSE], na.rm = TRUE),
            MEDIAN_NORM_COV = matrixStats::rowMedians(nm, na.rm = TRUE),
            Q05_NORM_COV = q[, 1],
            Q95_NORM_COV = q[, 2],
            FRAC_SAMPLES_NORM_COV_LT_0.2 = matrixStats::rowMeans2(nm < 0.2, na.rm = TRUE)
        )
    }
    targetSummary <- c("Normal", "Tumor") |>
        map(target_stats) |>
        bind_rows() |>
        separate_wider_regex(TARGET, c(CHROM = "[^:]+", ":", START = "\\d+", "-", END = "\\d+"), cols_remove = FALSE) |>
        mutate(across(c(START, END), as.integer))

    #
    # Per-sample uniformity: fraction of targets below 0.2x and above 2x
    # the sample median, interquartile range of normalized coverage, and
    # fraction of targets with zero coverage
    #
    # TARGET_MEDIAN_COV is the median of Alfred per-target mean coverage.
    # It counts duplicates, so it runs higher than
    # HSM_MEDIAN_TARGET_COVERAGE, and it has no coverage cap
    targetSampleMetrics <- tibble(
        SAMPLE = colnames(covMat),
        TARGET_MEDIAN_COV = matrixStats::colMedians(covMat, na.rm = TRUE),
        TARGET_FRAC_NORM_COV_LT_0.2 = matrixStats::colMeans2(normMat < 0.2, na.rm = TRUE),
        TARGET_FRAC_NORM_COV_GT_2 = matrixStats::colMeans2(normMat > 2, na.rm = TRUE),
        TARGET_IQR_NORM_COV = matrixStats::colIQRs(normMat, na.rm = TRUE),
        TARGET_FRAC_ZERO_COV = matrixStats::colMeans2(covMat == 0, na.rm = TRUE)
    )
    rm(covMat, normMat)
    alfred <- map(alfred, \(a) if (is.null(a)) NULL else list_modify(a, targetCov = zap()))
    invisible(gc())
}

#
# Per-pair QC
#
message("Reading per-pair QC")

concordance <- find_files(somDir, "\\.concordance\\.txt$") |> map_files(read_concordance, "conpair_concordance") |> bind_rows()
contamination <- find_files(somDir, "\\.contamination\\.txt$") |> map_files(read_contamination, "conpair_contamination") |> bind_rows()
facetsQC <- find_files(somDir, "/facets/[^/]+/[^/]+\\.facets_qc\\.txt$") |> map_files(read_facets_qc, "facets_qc") |>
    bind_rows() |>
    convert_facets_qc()
sampleData <- find_files(somDir, "\\.sample_data\\.txt$") |> map_files(read_sample_data, "sample_data") |> bind_rows()
statusPair <- find_files(somDir, "/multiqc/[^/]+\\.QC_Status\\.txt$") |> map_files(read_tempo_status, "tempo_status_pair") |> bind_rows()
manta <- find_files(somDir, "\\.manta\\.vcf\\.gz$") |> map_files(read_manta_count, "manta") |> bind_rows()

read_maf_bundle <- function(file) {
    pair <- basename(file) |> str_remove("\\.somatic\\.(final|unfiltered)\\.maf$")
    maf <- read_maf(file)
    list(pair = pair, maf = maf)
}

message("Reading MAFs")
mafFinal <- find_files(somDir, "\\.somatic\\.final\\.maf$") |>
    map_files(\(f) {
        b <- read_maf_bundle(f)
        list(
            summary = summarize_maf(b$maf, b$pair, "MAF_"),
            spectrum = maf_spectrum(b$maf, b$pair)
        )
    }, "maf_final")
mafUnfilt <- find_files(somDir, "\\.somatic\\.unfiltered\\.maf$") |>
    map_files(\(f) {
        b <- read_maf_bundle(f)
        list(
            summary = summarize_maf(b$maf, b$pair, "MAFUNFILT_"),
            filters = maf_filter_counts(b$maf, b$pair)
        )
    }, "maf_unfiltered")

#
# Assemble the per-sample table (one row per sample)
#
message("Assembling tables")

contamBySample <- contamination |>
    select(SAMPLE, CONPAIR_CONTAMINATION) |>
    distinct(SAMPLE, .keep_all = TRUE)
facetsPrefixed <- facetsQC |>
    rename_with(\(x) str_c("FACETS_", x), -PAIR)

sampleMetrics <- sampleMap |>
    distinct(SAMPLE, TYPE) |>
    left_join(hsmMetrics, by = "SAMPLE") |>
    left_join(asmMetrics, by = "SAMPLE") |>
    left_join(alfredMetrics, by = "SAMPLE") |>
    left_join(onTargetMetrics, by = "SAMPLE") |>
    left_join(sexMetrics, by = "SAMPLE") |>
    left_join(targetSampleMetrics, by = "SAMPLE") |>
    left_join(qualimapMetrics, by = "SAMPLE") |>
    left_join(fastpMetrics, by = "SAMPLE") |>
    left_join(contamBySample, by = "SAMPLE") |>
    left_join(statusSample |> distinct(SAMPLE, .keep_all = TRUE), by = "SAMPLE")

pairMetrics <- pairing |>
    select(PAIR, TUMOR_ID, NORMAL_ID) |>
    left_join(concordance, by = "PAIR") |>
    left_join(sampleData, by = "PAIR") |>
    left_join(facetsPrefixed, by = "PAIR") |>
    left_join(pluck_bind(mafFinal, "summary"), by = "PAIR") |>
    left_join(pluck_bind(mafUnfilt, "summary"), by = "PAIR") |>
    left_join(manta, by = "PAIR")

#
# Pair-level Tempo status: the worst status of the samples in the
# somatic QC_Status file (fail > warn > pass), with the non-pass reasons
#
if (nrow(statusPair) > 0) {
    samplePair <- sampleMap |>
        select(SAMPLE, PAIR)
    statusRank <- c(pass = 1, warn = 2, fail = 3)
    pairStatus <- statusPair |>
        left_join(samplePair, by = "SAMPLE", relationship = "many-to-many") |>
        group_by(PAIR) |>
        summarize(
            TEMPO_PAIR_QC_STATUS = TEMPO_QC_STATUS[which.max(statusRank[TEMPO_QC_STATUS])],
            TEMPO_PAIR_QC_REASON = str_c(unique(TEMPO_QC_REASON[TEMPO_QC_STATUS != "pass"]), collapse = ";"),
            .groups = "drop"
        )
    pairMetrics <- pairMetrics |>
        left_join(pairStatus, by = "PAIR")
}

#
# Sample metadata (LIMS), if given
#
samples <- sampleMap
if (!is.null(opt$lims)) {
    lims <- read_csv(opt$lims, show_col_types = FALSE, col_types = cols(.default = "c"))
    if (!limsKey %in% names(lims)) stop(glue("--lims has no column {limsKey}"), call. = FALSE)
    lims <- lims |>
        select(-any_of(c("paths", "deliveryPath", "labHeadEmail", "investigatorEmail"))) |>
        rename(SAMPLE = all_of(limsKey)) |>
        distinct(SAMPLE, .keep_all = TRUE)
    samples <- samples |> left_join(lims, by = "SAMPLE")
    message(glue("LIMS rows matched: {sum(samples$SAMPLE %in% lims$SAMPLE)} of {nrow(samples)}"))
}

#
# Long tables and reference distributions
#
numeric_long <- function(df, idCols) {
    df |>
        select(all_of(idCols), where(is.numeric)) |>
        pivot_longer(-all_of(idCols), names_to = "METRIC", values_to = "VALUE") |>
        mutate(SOURCE = str_extract(METRIC, "^[A-Z]+(?=_)"), .before = METRIC)
}

sampleLong <- numeric_long(sampleMetrics, c("SAMPLE", "TYPE"))
pairLong <- numeric_long(pairMetrics |> mutate(TYPE = "Pair"), c("PAIR", "TYPE"))

ref_stats <- function(long) {
    probs <- c(0.01, 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 0.99)
    long |>
        filter(is.finite(VALUE)) |>
        group_by(TYPE, SOURCE, METRIC) |>
        summarize(
            N = n(),
            MEAN = mean(VALUE),
            SD = sd(VALUE),
            MEDIAN = median(VALUE),
            MAD = mad(VALUE),
            MIN = min(VALUE),
            MAX = max(VALUE),
            as_tibble_row(set_names(quantile(VALUE, probs, names = FALSE), str_c("Q", sprintf("%02d", probs * 100)))),
            .groups = "drop"
        )
}

reference <- bind_rows(
    ref_stats(sampleLong),
    ref_stats(sampleLong |> mutate(TYPE = "All")),
    ref_stats(pairLong)
) |>
    arrange(SOURCE, METRIC, TYPE)

#
# Histograms and distributions (long, per sample or per pair)
#
dist <- list(
    hsm_coverage = pluck_bind(hsm, "hist"),
    asm_categories = pluck_bind(asm, "categories"),
    alfred_insert_size = pluck_bind(alfred, "insertSize"),
    alfred_coverage = pluck_bind(alfred, "coverage"),
    alfred_gc = pluck_bind(alfred, "gc"),
    alfred_base_qual = pluck_bind(alfred, "baseQual"),
    alfred_map_qual = pluck_bind(alfred, "mapQual"),
    alfred_chrom_map = chromMap,
    alfred_indel_size = pluck_bind(alfred, "indelSize"),
    alfred_indel_context = pluck_bind(alfred, "indelContext"),
    alfred_on_target = onTarget,
    fastp_lanes = fastpLanes,
    maf_spectrum96 = pluck_bind(mafFinal, "spectrum"),
    maf_unfiltered_filters = pluck_bind(mafUnfilt, "filters")
)

#
# Pipeline resource usage from the Nextflow trace files
#
traceFiles <- find_files(file.path(outDir, "pipeline_info"), "execution_trace.*\\.txt$")
trace <- traceFiles |> map(read_trace) |> bind_rows()
pipeline <- if (nrow(trace) > 0) {
    trace |>
        group_by(PROCESS) |>
        summarize(
            N_TASKS = n(),
            N_COMPLETED = sum(status == "COMPLETED"),
            N_FAILED = sum(status == "FAILED"),
            MAX_ATTEMPT = max(as.integer(attempt), na.rm = TRUE),
            MEDIAN_REALTIME_H = median(REALTIME_H, na.rm = TRUE),
            MAX_REALTIME_H = suppressWarnings(max(REALTIME_H, na.rm = TRUE)),
            MEDIAN_PEAK_RSS_GB = median(PEAK_RSS_GB, na.rm = TRUE),
            MAX_PEAK_RSS_GB = suppressWarnings(max(PEAK_RSS_GB, na.rm = TRUE)),
            .groups = "drop"
        )
} else {
    tibble()
}

#
# Completeness: which samples and pairs have each source
#
has_rows <- function(ids, df, key) ids %in% (df[[key]] %||% character())
completeness <- list(
    samples = sampleMap |>
        distinct(SAMPLE, TYPE) |>
        mutate(
            HSM = has_rows(SAMPLE, hsmMetrics, "SAMPLE"),
            ASM = has_rows(SAMPLE, asmMetrics, "SAMPLE"),
            ALFRED = has_rows(SAMPLE, alfredMetrics, "SAMPLE"),
            QUALIMAP = has_rows(SAMPLE, qualimapMetrics, "SAMPLE"),
            FASTP = has_rows(SAMPLE, fastpMetrics, "SAMPLE"),
            CONPAIR = has_rows(SAMPLE, contamination, "SAMPLE"),
            TEMPO_STATUS = has_rows(SAMPLE, statusSample, "SAMPLE")
        ),
    pairs = pairing |>
        select(PAIR) |>
        mutate(
            CONCORDANCE = has_rows(PAIR, concordance, "PAIR"),
            FACETS = has_rows(PAIR, facetsQC, "PAIR"),
            SAMPLE_DATA = has_rows(PAIR, sampleData, "PAIR"),
            MAF_FINAL = has_rows(PAIR, pluck_bind(mafFinal, "summary"), "PAIR"),
            MAF_UNFILTERED = has_rows(PAIR, pluck_bind(mafUnfilt, "summary"), "PAIR"),
            MANTA = has_rows(PAIR, manta, "PAIR")
        ),
    failed_files = failedFiles
)

#
# Data dictionary: every column of the two metric tables and its source
#
sourceNames <- c(
    HSM = "Picard CollectHsMetrics",
    ASM = "Picard CollectAlignmentSummaryMetrics, PAIR row (all reads, duplicates included)",
    ALFRED = "Alfred qc (whole BAM)",
    TARGET = "Alfred per-target coverage (TC), normalized to sample median",
    QUALIMAP = "Qualimap bamqc genome_results.txt", FASTP = "fastp, summed over lanes",
    CONPAIR = "Conpair", TEMPO = "Tempo (sample_data.txt, multiqc QC_Status)",
    FACETS = "facets-suite QC (facets_qc.txt)", MAF = "somatic.final.maf summary",
    MAFUNFILT = "somatic.unfiltered.maf summary", MANTA = "Manta somatic VCF"
)
dictionary <- bind_rows(
    tibble(TABLE = "sample_metrics", COLUMN = names(sampleMetrics), CLASS = map_chr(sampleMetrics, \(x) class(x)[1])),
    tibble(TABLE = "pair_metrics", COLUMN = names(pairMetrics), CLASS = map_chr(pairMetrics, \(x) class(x)[1]))
) |>
    mutate(
        SOURCE = str_extract(COLUMN, "^[A-Z]+(?=_)"),
        SOURCE_DESCRIPTION = unname(sourceNames[SOURCE])
    )

#
# Metadata and save
#
git_rev <- function(dir) {
    tryCatch(system2("git", c("-C", dir, "rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = FALSE),
             error = \(e) NA_character_, warning = \(w) NA_character_)
}

meta <- list(
    name = "adagio QC background database",
    assay = assay,
    version = version,
    created = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    project_id = projectId,
    source_out_dir = outDir,
    n_pairs = nrow(pairing),
    n_samples = n_distinct(sampleMap$SAMPLE),
    n_samples_by_type = sampleMap |> distinct(SAMPLE, TYPE) |> count(TYPE),
    adagio_commit = git_rev(ADAGIO),
    tempo_commit = git_rev(file.path(ADAGIO, "tempo")),
    builder = "scripts/qcdb/buildQCDb.R",
    r_version = R.version.string,
    lims_file = opt$lims %||% NA_character_,
    hsmetrics_dir = hsmDir,
    hsmetrics_coverage_cap = hsmCap,
    asm_dir = asmDir,
    notes = c(
        glue("HSM_ metrics and hsm_coverage come from {hsmDir}; Picard COVERAGE_CAP {hsmCap} caps ",
             "HSM_MEDIAN_TARGET_COVERAGE, FOLD_80_BASE_PENALTY, HS_PENALTY_* and the histogram."),
        glue("ASM_ metrics are the PAIR row of Picard CollectAlignmentSummaryMetrics from {asmDir}; ",
             "dist$asm_categories has the FIRST_OF_PAIR, SECOND_OF_PAIR and PAIR rows."),
        "CONPAIR_CONTAMINATION is a fraction (Conpair percent / 100).",
        "Target coverage summaries use Alfred TC AvgCov normalized to each sample's median target coverage.",
        "alfred_insert_size is capped at 1000 bp and alfred_coverage at 500x (genome-wide, not target).",
        "reference holds per-metric distribution summaries by TYPE (Normal, Tumor, All, Pair)."
    )
)

qcdb <- list(
    meta = meta,
    samples = samples,
    pairs = pairing |> select(PAIR, TUMOR_ID, NORMAL_ID),
    sample_metrics = sampleMetrics,
    pair_metrics = pairMetrics,
    sample_metrics_long = sampleLong,
    pair_metrics_long = pairLong,
    reference = reference,
    target_coverage = targetSummary,
    dist = dist,
    pipeline = pipeline,
    completeness = completeness,
    dictionary = dictionary
)

fs::dir_create(destDir)
saveRDS(qcdb, outFile, compress = "xz")

message(glue("\nWrote {outFile} ({round(fs::file_size(outFile) / 1024^2, 1)} MB)"))
message(glue("Samples: {nrow(sampleMetrics)}  Pairs: {nrow(pairMetrics)}"))
message(glue("Sample metrics: {ncol(sampleMetrics) - 2}  Pair metrics: {ncol(pairMetrics) - 3}"))
message("Completeness (samples with each source):")
completeness$samples |> summarize(across(where(is.logical), sum)) |> print()
message("Completeness (pairs with each source):")
completeness$pairs |> summarize(across(where(is.logical), sum)) |> print()
if (nrow(failedFiles) > 0) message(glue("Files that failed to parse: {nrow(failedFiles)}"))
message(glue("\nAdd this line to {file.path(ADAGIO, 'assets', 'qcdb', 'qcdb_index.tsv')}:"))
message(glue("{assay}\t{version}\t{format(Sys.Date(), '%Y-%m-%d')}\t{normalizePath(outFile)}"))
