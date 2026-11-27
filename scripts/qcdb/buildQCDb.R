#
# buildQCDb.R
#
# Build a QC background database from the outputs of one or more
# finished Tempo (adagio) runs. The database is one .rds file holding a
# list of tibbles; see README.md in this folder for the layout.
#
# Run from the project folder (the one that holds out/), or pass --out.
# This reads every QC file of every sample, so submit it with
# runBuildQCDb.sh rather than running it on an interactive node.
#

usage <- function() {
    cat("
Usage: Rscript buildQCDb.R [options]

Build the QC background database (.rds) from one or more finished adagio
runs. Options marked [list] take a comma-separated list; with several
--out folders, give one value per folder, in the same order.

Options:
  --out=DIR[,DIR]       project output folders, out/<PROJECT_ID> [list]
                        (default: the only project folder under ./out)
  --pairing=FILE[,FILE] pairing file NORMAL_ID<TAB>TUMOR_ID with header
                        [list] (default: the one recorded in each run's
                        runlog/cmd.sh.log)
  --lims=FILE[,FILE]    optional sample metadata CSVs with one row per
                        sample, joined on the column given by --lims-key;
                        any number of files, rows are combined
  --lims-key=COL        sample ID column in --lims (default: dir_sample_name)
  --hsmetrics=DIR[,DIR] folder of <SAMPLE>.hs_metrics.txt files [list]
                        (default: <out>/post/qc, written by
                        scripts/picardqc/doPicardQC.sh without Tempo's 200x
                        cap; <out>/bams reads Tempo's capped files)
  --asm=DIR[,DIR]       folder of <SAMPLE>.asm.txt files, Picard
                        CollectAlignmentSummaryMetrics [list] (default:
                        <out>/post/qc, written by scripts/picardqc/doPicardQC.sh)
  --target-gc=FILE      per-target GC table from makeTargetGC.R (default for
                        WES_IDT_v2: <adagio>/assets/qcdb/
                        IDT_Exome_v2_FP_b37_targets.plus5bp.gc.tsv.gz)
  --genes=DIR           gene resources from scripts/qcgenes/buildQCGenes.R
                        (default: QC_GENES_DIR in scripts/rsrc/qc_pair_data.R)
  --assay=LABEL         assay label used in the file name (default: WES_IDT_v2)
  --version=V           version label (default: the build date, yymmdd)
  --dest=DIR            output folder (default: ./qcdb in the project folder)
  --cores=N             parallel workers (default: SLURM_CPUS_PER_TASK or 1)
  -h, --help            show this help

Output: <dest>/qcdb_<assay>_<version>.rds. An existing file is never
overwritten; give a new --version instead. A sample may be in only one
run.

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
source(file.path(SDIR, "rsrc", "qcdb_seq_tech.R"))
source(file.path(ADAGIO, "scripts", "rsrc", "read_pairing.R"))
# gene_mvlh(), read_gene_resources() and call_normal_sex(): the
# functions the per-pair QC pages use, so background and project match
source(file.path(ADAGIO, "scripts", "rsrc", "qc_pair_data.R"))
source(file.path(ADAGIO, "scripts", "rsrc", "qc_sex.R"))

nCores <- as.integer(opt$cores %||% Sys.getenv("SLURM_CPUS_PER_TASK", "1"))
assay <- opt$assay %||% "WES_IDT_v2"
destDir <- opt$dest %||% "qcdb"
limsKey <- opt[["lims-key"]] %||% "dir_sample_name"

# Comma-separated option value as a vector; NULL when not given
split_opt <- function(x) {
    if (is.null(x)) return(NULL)
    str_split_1(x, ",") |>
        str_trim() |>
        discard(\(s) s == "")
}

# Per-target GC table for the GC-bias curves, by assay
TARGET_GC_FILES <- c(WES_IDT_v2 = "IDT_Exome_v2_FP_b37_targets.plus5bp.gc.tsv.gz")
targetGcFile <- opt[["target-gc"]] %||%
    (if (assay %in% names(TARGET_GC_FILES)) file.path(ADAGIO, "assets", "qcdb", TARGET_GC_FILES[[assay]]) else NA)
if (is.na(targetGcFile) || !fs::file_exists(targetGcFile)) {
    stop(glue("No per-target GC table for {assay} ({targetGcFile}); build one with makeTargetGC.R ",
              "and pass --target-gc"), call. = FALSE)
}
targetGcFile <- normalizePath(targetGcFile)
genesDir <- normalizePath(opt$genes %||% QC_GENES_DIR, mustWork = TRUE)

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
# Locate the runs
#
outDirs <- split_opt(opt$out)
if (is.null(outDirs)) {
    outDirs <- fs::dir_ls("out", type = "directory") |>
        str_subset("/metrics$", negate = TRUE)
    if (len(outDirs) != 1) stop("Cannot pick a project folder under ./out; use --out", call. = FALSE)
}
outDirs <- normalizePath(outDirs, mustWork = TRUE)
projectIds <- basename(outDirs)
if (any(duplicated(projectIds))) {
    stop(glue("Two --out folders have the same project ID: {str_c(projectIds, collapse = ', ')}"), call. = FALSE)
}
message(str_c(glue("Run {seq_along(outDirs)}: {projectIds}, {outDirs}"), collapse = "\n"))

# One value per run for a [list] option, or the default
per_run <- function(name, default) {
    vals <- split_opt(opt[[name]])
    if (is.null(vals)) return(default)
    if (len(vals) != len(outDirs)) {
        stop(glue("--{name} needs one value per --out folder ({len(outDirs)})"), call. = FALSE)
    }
    vals
}

pairingFiles <- per_run("pairing", rep(NA_character_, len(outDirs)))
pairing <- map2(outDirs, pairingFiles, \(o, p) {
    pr <- if (is.na(p)) read_pairing(o) else read_tsv_quiet(p) |> select(NORMAL_ID, TUMOR_ID)
    pr |>
        distinct() |>
        mutate(PROJECT_ID = basename(o))
}) |>
    bind_rows() |>
    mutate(PAIR = str_c(TUMOR_ID, "__", NORMAL_ID))
message(glue("Pairs in pairing files: {nrow(pairing)}"))

sampleMap <- bind_rows(
    pairing |> transmute(SAMPLE = TUMOR_ID, TYPE = "Tumor", PAIR, PROJECT_ID),
    pairing |> transmute(SAMPLE = NORMAL_ID, TYPE = "Normal", PAIR, PROJECT_ID)
)

# A sample in two runs would have two sets of QC files
inTwoRuns <- sampleMap |>
    distinct(SAMPLE, PROJECT_ID) |>
    filter(n() > 1, .by = SAMPLE)
if (nrow(inTwoRuns) > 0) {
    stop(glue("Samples in more than one run: {str_c(unique(inTwoRuns$SAMPLE), collapse = ', ')}"), call. = FALSE)
}

if (any(duplicated(sampleMap$SAMPLE))) {
    message("NOTE: some samples are in more than one pair; sample metrics are joined to each pair")
}

bamDirs <- file.path(outDirs, "bams")
somDirs <- file.path(outDirs, "somatic")

# QC files of each run in its folder; stops if a run has none
find_run_files <- function(dirs, re, hint) {
    files <- map(dirs, \(d) if (fs::dir_exists(d)) find_files(d, re) else character())
    empty <- dirs[lengths(files) == 0]
    if (len(empty) > 0) stop(glue("No {re} files in {str_c(empty, collapse = ', ')}\n{hint}"), call. = FALSE)
    unlist(files)
}

#
# HsMetrics: by default the files from scripts/picardqc/doPicardQC.sh,
# which reruns Picard without Tempo's COVERAGE_CAP of 200
#
hsmDirs <- per_run("hsmetrics", file.path(outDirs, "post", "qc")) |> normalizePath(mustWork = FALSE)
hsmFiles <- find_run_files(hsmDirs, "\\.hs_metrics\\.txt$",
                           glue("Run scripts/picardqc/doPicardQC.sh first, or use --hsmetrics=<out>/bams ",
                                "for Tempo's files (capped at 200x)"))

#
# Picard CollectAlignmentSummaryMetrics: Tempo does not run it;
# scripts/picardqc/doPicardQC.sh does
#
asmDirs <- per_run("asm", file.path(outDirs, "post", "qc")) |> normalizePath(mustWork = FALSE)
asmFiles <- find_run_files(asmDirs, "\\.asm\\.txt$", "Run scripts/picardqc/doPicardQC.sh first (-t asm)")
message(glue("AlignmentSummaryMetrics: {str_c(asmDirs, collapse = ', ')}"))
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
    stop(glue("HsMetrics files in {str_c(hsmDirs, collapse = ', ')} use different COVERAGE_CAP values: ",
              "{str_c(hsmCap, collapse = ', ')}"), call. = FALSE)
}
message(glue("HsMetrics: {str_c(hsmDirs, collapse = ', ')} (COVERAGE_CAP {hsmCap})"))

#
# Sample metadata (LIMS), if given: one table from all --lims files
#
limsFiles <- split_opt(opt$lims)
lims <- NULL
if (!is.null(limsFiles)) {
    lims <- limsFiles |>
        map(\(f) {
            l <- read_csv(f, show_col_types = FALSE, col_types = cols(.default = "c"))
            if (!limsKey %in% names(l)) stop(glue("--lims {f} has no column {limsKey}"), call. = FALSE)
            l
        }) |>
        bind_rows() |>
        select(-any_of(c("paths", "deliveryPath", "labHeadEmail", "investigatorEmail"))) |>
        rename(SAMPLE = all_of(limsKey)) |>
        distinct(SAMPLE, .keep_all = TRUE)
}

# Reported sex (Male, Female) from the LIMS sex column, as
# read_reported_sex() reads a project's metadata
reportedSex <- if (!is.null(lims) && "sex" %in% names(lims)) {
    lims |>
        transmute(SAMPLE, REPORTED = case_when(
            str_detect(str_to_upper(sex), "^M") ~ "Male",
            str_detect(str_to_upper(sex), "^F") ~ "Female"
        ))
} else {
    tibble(SAMPLE = character(), REPORTED = character())
}

#
# Resources for the per-target tables: GC of each target, and the genes
# and gene-to-target map of the missed-variant likelihood
#
gcTable <- read_target_gc(targetGcFile)
genes <- read_gene_resources(genesDir, assay)
message(glue("Target GC: {targetGcFile} ({nrow(gcTable)} targets)\nGene resources: {genesDir}"))

#
# Per-sample QC
#
message("Reading per-sample QC")

hsm <- hsmFiles |> map_files(read_hs_metrics, "hs_metrics")
asm <- asmFiles |> map_files(read_asm, "asm")
alfred <- find_files(bamDirs, "/alfred/[^/]+\\.alfred\\.tsv\\.gz$") |> map_files(read_alfred, "alfred")
qualimap <- find_files(bamDirs, "_qualimap_rawdata\\.tar\\.gz$") |> map_files(read_qualimap, "qualimap")
fastpFiles <- find_files(bamDirs, "\\.fastp\\.json$")
fastpLanes <- fastpFiles |> map_files(read_fastp, "fastp") |> bind_rows()
fastpDupHist <- fastpFiles |> map_files(read_fastp_dup_hist, "fastp_dup_hist") |> bind_rows()
statusSample <- find_files(bamDirs, "/multiqc/[^/]+\\.QC_Status\\.txt$") |>
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
# FACETS, read before the per-target coverage: the missed-variant
# likelihood needs each tumor's purity
#
facetsQC <- find_files(somDirs, "/facets/[^/]+/[^/]+\\.facets_qc\\.txt$") |>
    map_files(read_facets_qc, "facets_qc") |>
    bind_rows() |>
    convert_facets_qc()
facetsGeneLevel <- find_files(somDirs, FACETS_GENE_LEVEL_RE) |>
    map_files(read_facets_gene_level, "facets_gene_level") |>
    bind_rows()
if (nrow(facetsGeneLevel) == 0) facetsGeneLevel <- tibble(PAIR = character(), FACETS_N_HOMDEL_GENES = numeric())

#
# Inputs of the missed-variant likelihood, one row per tumor: Picard
# mean target coverage, FACETS purity (NA when FACETS has none; no MVLH
# then), and the sex from the normal's call with the reported sex as
# fallback, as the per-pair QC pages decide it
#
facetsPurity <- if ("purity" %in% names(facetsQC)) {
    facetsQC |> select(PAIR, PURITY = purity)
} else {
    tibble(PAIR = character(), PURITY = numeric())
}
hsmMean <- hsmMetrics |>
    select(SAMPLE, HSM_MEAN_TARGET_COVERAGE)
normalXY <- sexMetrics |>
    select(NORMAL_ID = SAMPLE, XN = ALFRED_CHRX_OBS_EXP, YN = ALFRED_CHRY_OBS_EXP)
reportedN <- reportedSex |>
    select(NORMAL_ID = SAMPLE, REP_N = REPORTED)
reportedT <- reportedSex |>
    select(SAMPLE, REP_T = REPORTED)
mvlhSamples <- pairing |>
    select(SAMPLE = TUMOR_ID, PAIR, NORMAL_ID) |>
    left_join(hsmMean, by = "SAMPLE") |>
    left_join(facetsPurity, by = "PAIR") |>
    left_join(normalXY, by = "NORMAL_ID") |>
    left_join(reportedN, by = "NORMAL_ID") |>
    left_join(reportedT, by = "SAMPLE") |>
    mutate(
        SEX_CALL = call_normal_sex(XN, YN),
        REPORTED_SEX = coalesce(REP_N, REP_T),
        MALE = mvlh_male(SEX_CALL, REPORTED_SEX)
    ) |>
    select(SAMPLE, PAIR, HSM_MEAN_TARGET_COVERAGE, PURITY, SEX_CALL, REPORTED_SEX, MALE)
if (any(duplicated(mvlhSamples$SAMPLE))) {
    stop("A tumor is in more than one pair; dist$gene_mvlh is keyed by SAMPLE", call. = FALSE)
}

#
# Parallel map over the columns of a matrix; stops on the first error
# (these are computations, not file parsing)
#
map_columns <- function(samples, fn) {
    res <- parallel::mclapply(samples, \(s) tryCatch(fn(s), error = \(e) e), mc.cores = nCores)
    failed <- map_lgl(res, \(x) inherits(x, c("error", "try-error")))
    if (any(failed)) stop(glue("{samples[failed][1]}: {conditionMessage(res[failed][[1]])}"), call. = FALSE)
    bind_rows(res)
}

#
# Per-target coverage. Each sample is normalized to its median target
# coverage; the database keeps per-target summaries across normals and
# across tumors (the full matrix is too large to ship).
#
message("Summarizing per-target coverage")
alfredOK <- compact(alfred)
targetSummary <- tibble()
targetSampleMetrics <- tibble(SAMPLE = character())
targetGcBias <- tibble(SAMPLE = character())
geneMvlh <- tibble(SAMPLE = character())
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
    rm(normMat)

    #
    # GC-bias curve of each sample, and the missed-variant likelihood of
    # each tumor over the OncoKB genes. Both take a sample's raw TC
    # coverage, as qcdb_project_metrics.R does for a project.
    #
    nNoGc <- sum(!unique(targetIds) %in% gcTable$TARGET)
    if (nNoGc > 0) message(glue("NOTE: {nNoGc} TC targets are not in {targetGcFile}"))
    message("GC-bias curves")
    targetGcBias <- map_columns(colnames(covMat), \(s) {
        target_gc_curve(covMat[, s], targetIds, gcTable) |>
            mutate(SAMPLE = s, .before = 1)
    })

    message("Missed-variant likelihood")
    mvlhRun <- mvlhSamples |>
        filter(SAMPLE %in% colnames(covMat))
    geneMvlh <- map_columns(seq_len(nrow(mvlhRun)), \(i) {
        r <- mvlhRun[i, ]
        m <- tumor_gene_mvlh(covMat[, r$SAMPLE], targetIds, r$HSM_MEAN_TARGET_COVERAGE, r$PURITY, r$MALE, genes)
        if (is.null(m)) NULL else m |> transmute(SAMPLE = r$SAMPLE, GENE, MVLH, MEAN_DEPTH)
    })
    if (nrow(geneMvlh) == 0) geneMvlh <- tibble(SAMPLE = character())

    rm(covMat)
    alfred <- map(alfred, \(a) if (is.null(a)) NULL else list_modify(a, targetCov = zap()))
    invisible(gc())
}

#
# Per-pair QC
#
message("Reading per-pair QC")

concordance <- find_files(somDirs, "\\.concordance\\.txt$") |> map_files(read_concordance, "conpair_concordance") |> bind_rows()
contamination <- find_files(somDirs, "\\.contamination\\.txt$") |> map_files(read_contamination, "conpair_contamination") |> bind_rows()
sampleData <- find_files(somDirs, "\\.sample_data\\.txt$") |> map_files(read_sample_data, "sample_data") |> bind_rows()
statusPair <- find_files(somDirs, "/multiqc/[^/]+\\.QC_Status\\.txt$") |> map_files(read_tempo_status, "tempo_status_pair") |> bind_rows()
manta <- find_files(somDirs, "\\.manta\\.vcf\\.gz$") |> map_files(read_manta_count, "manta") |> bind_rows()

read_maf_bundle <- function(file) {
    pair <- basename(file) |> str_remove("\\.somatic\\.(final|unfiltered)\\.maf$")
    maf <- read_maf(file)
    list(pair = pair, maf = maf)
}

message("Reading MAFs")
mafFinal <- find_files(somDirs, "\\.somatic\\.final\\.maf$") |>
    map_files(\(f) {
        b <- read_maf_bundle(f)
        list(
            summary = summarize_maf(b$maf, b$pair, "MAF_"),
            spectrum = maf_spectrum(b$maf, b$pair)
        )
    }, "maf_final")
mafUnfilt <- find_files(somDirs, "\\.somatic\\.unfiltered\\.maf$") |>
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
    left_join(facetsGeneLevel, by = "PAIR") |>
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
# Sample table: run, sequencer technology (qcdb_seq_tech.R, as
# qcReport02.R computes it) and LIMS metadata, if given
#
seqTech <- if (nrow(fastpLanes) > 0) {
    sample_seq_tech(fastpLanes)
} else {
    tibble(SAMPLE = character(), SEQ_TECH = character(), INSTRUMENT = character())
}
samples <- sampleMap |>
    left_join(seqTech, by = "SAMPLE")
if (!is.null(lims)) {
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
mvlhGeneCounts <- geneMvlh |>
    count(SAMPLE, name = "N_GENES")
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
    fastp_dup_hist = fastpDupHist,
    target_gc_bias = targetGcBias,
    gene_mvlh = geneMvlh,
    gene_mvlh_samples = mvlhSamples |>
        left_join(mvlhGeneCounts, by = "SAMPLE") |>
        mutate(N_GENES = coalesce(N_GENES, 0L)),
    maf_spectrum96 = pluck_bind(mafFinal, "spectrum"),
    maf_unfiltered_filters = pluck_bind(mafUnfilt, "filters")
)

#
# Pipeline resource usage from the Nextflow trace files, per run
#
trace <- outDirs |>
    map(\(o) {
        find_files(file.path(o, "pipeline_info"), "execution_trace.*\\.txt$") |>
            map(read_trace) |>
            bind_rows() |>
            mutate(PROJECT_ID = basename(o))
    }) |>
    bind_rows()
pipeline <- if (nrow(trace) > 0) {
    trace |>
        group_by(PROJECT_ID, PROCESS) |>
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
    # GENE_MVLH is for tumors only (NA for normals); a tumor without it
    # has no FACETS purity (see dist$gene_mvlh_samples)
    samples = sampleMap |>
        distinct(SAMPLE, TYPE, PROJECT_ID) |>
        mutate(
            HSM = has_rows(SAMPLE, hsmMetrics, "SAMPLE"),
            ASM = has_rows(SAMPLE, asmMetrics, "SAMPLE"),
            ALFRED = has_rows(SAMPLE, alfredMetrics, "SAMPLE"),
            QUALIMAP = has_rows(SAMPLE, qualimapMetrics, "SAMPLE"),
            FASTP = has_rows(SAMPLE, fastpMetrics, "SAMPLE"),
            FASTP_DUP_HIST = has_rows(SAMPLE, fastpDupHist, "SAMPLE"),
            TARGET_GC_BIAS = has_rows(SAMPLE, targetGcBias, "SAMPLE"),
            GENE_MVLH = if_else(TYPE == "Tumor", has_rows(SAMPLE, geneMvlh, "SAMPLE"), NA),
            CONPAIR = has_rows(SAMPLE, contamination, "SAMPLE"),
            TEMPO_STATUS = has_rows(SAMPLE, statusSample, "SAMPLE")
        ),
    pairs = pairing |>
        select(PAIR, PROJECT_ID) |>
        mutate(
            CONCORDANCE = has_rows(PAIR, concordance, "PAIR"),
            FACETS = has_rows(PAIR, facetsQC, "PAIR"),
            FACETS_GENE_LEVEL = has_rows(PAIR, facetsGeneLevel, "PAIR"),
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
    FACETS = "facets-suite QC (facets_qc.txt); FACETS_N_HOMDEL_GENES from gene_level.txt (PASS, RESCUE)",
    MAF = "somatic.final.maf summary",
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

# TRUE when the adagio working tree has changes not in adagio_commit
git_dirty <- function(dir) {
    st <- tryCatch(system2("git", c("-C", dir, "status", "--porcelain"), stdout = TRUE, stderr = FALSE),
                   error = \(e) NA_character_, warning = \(w) NA_character_)
    if (identical(st, NA_character_)) NA else len(st) > 0
}

meta <- list(
    name = "adagio QC background database",
    assay = assay,
    version = version,
    created = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    project_id = projectIds,
    source_out_dir = outDirs,
    n_pairs = nrow(pairing),
    n_samples = n_distinct(sampleMap$SAMPLE),
    n_samples_by_type = sampleMap |> distinct(SAMPLE, TYPE) |> count(TYPE),
    n_by_project = sampleMap |>
        distinct(SAMPLE, TYPE, PROJECT_ID) |>
        count(PROJECT_ID, TYPE),
    n_samples_by_seq_tech = samples |>
        distinct(SAMPLE, TYPE, SEQ_TECH) |>
        count(SEQ_TECH, TYPE),
    adagio_commit = git_rev(ADAGIO),
    adagio_dirty = git_dirty(ADAGIO),
    tempo_commit = git_rev(file.path(ADAGIO, "tempo")),
    builder = "scripts/qcdb/buildQCDb.R",
    r_version = R.version.string,
    lims_file = limsFiles %||% NA_character_,
    hsmetrics_dir = hsmDirs,
    hsmetrics_coverage_cap = hsmCap,
    asm_dir = asmDirs,
    target_gc_file = targetGcFile,
    qc_genes_dir = genesDir,
    notes = c(
        glue("HSM_ metrics and hsm_coverage come from {str_c(hsmDirs, collapse = ', ')}; Picard COVERAGE_CAP ",
             "{hsmCap} caps HSM_MEDIAN_TARGET_COVERAGE, FOLD_80_BASE_PENALTY, HS_PENALTY_* and the histogram."),
        glue("ASM_ metrics are the PAIR row of Picard CollectAlignmentSummaryMetrics from ",
             "{str_c(asmDirs, collapse = ', ')}; dist$asm_categories has the FIRST_OF_PAIR, SECOND_OF_PAIR ",
             "and PAIR rows."),
        "CONPAIR_CONTAMINATION is a fraction (Conpair percent / 100).",
        "Target coverage summaries use Alfred TC AvgCov normalized to each sample's median target coverage.",
        "alfred_insert_size is capped at 1000 bp and alfred_coverage at 500x (genome-wide, not target).",
        str_c("reference holds per-metric distribution summaries by TYPE (Normal, Tumor, All, Pair), over every ",
              "sample of every run and sequencer technology."),
        str_c("fastp_dup_hist is per lane and sequence-based (first 12 bases of R1, first 32 of R2, before ",
              "alignment): duplicates in other lanes are not seen, and sequencing errors split sets."),
        glue("target_gc_bias: GC from {targetGcFile}; autosomal targets, 1% GC bins with 100 or more targets."),
        glue("gene_mvlh: tumors with a FACETS purity, OncoKB genes from {genesDir}; each target's mean Alfred ",
             "depth is used for all its bases, rescaled to HSM_MEAN_TARGET_COVERAGE, which underestimates MVLH ",
             "where depth varies within a target.")
    )
)

qcdb <- list(
    meta = meta,
    samples = samples,
    pairs = pairing |> select(PAIR, TUMOR_ID, NORMAL_ID, PROJECT_ID),
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
message("Samples by run and sequencer technology:")
samples |> distinct(SAMPLE, PROJECT_ID, SEQ_TECH) |> count(PROJECT_ID, SEQ_TECH) |> print()
message("Completeness (samples with each source; GENE_MVLH: tumors only):")
completeness$samples |> summarize(across(where(is.logical), \(x) sum(x, na.rm = TRUE))) |> print()
message("Completeness (pairs with each source):")
completeness$pairs |> summarize(across(where(is.logical), sum)) |> print()
if (nrow(failedFiles) > 0) message(glue("Files that failed to parse: {nrow(failedFiles)}"))
message(glue("\nAdd this line to {file.path(ADAGIO, 'assets', 'qcdb', 'qcdb_index.tsv')}:"))
message(glue("{assay}\t{version}\t{format(Sys.Date(), '%Y-%m-%d')}\t{normalizePath(outFile)}"))
