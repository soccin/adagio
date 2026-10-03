
# FACETS Report Generation Script
# ==============================
# This script processes FACETS copy number analysis results and generates
# consolidated reports in both TSV and Excel formats.
#
# Key outputs:
# - Individual segmentation files (purity and hisens modes)
# - Multi-sheet Excel workbook with run info, arm-level, and gene-level CNAs

suppressPackageStartupMessages({
  library(tidyverse)
  library(readxl)
  library(openxlsx)
})

# Command-line options
# ====================
# Handle --help before any file access so it works outside a project directory

usage <- "
reportFacets01.R -- FACETS copy number report

Usage:
  Rscript reportFacets01.R [options]

Processes FACETS copy number results from the Tempo output tree and writes
consolidated segmentation and Excel reports. Run from the project directory
(the one containing out/).

Options:
  --keep-failed   Include samples that failed the sample filter. By default a
                  sample is kept if it passed FACETS QC or has
                  |dipLogR| < 0.5; other samples are dropped from the
                  segmentation and CNA tables. Output filenames are tagged
                  NO_FILT when this is set.
  -h, --help      Print this message and exit.

Outputs:
  post/reports/Proj_<no>[_NO_FILT]_facets_v4.xlsx
      Multi-sheet workbook: runInfo, armLevel, geneLevelFocal, facetsQC,
      facetsParams.
  post/plots/facets/Proj_<no>_{Filtered,NO_FILT}_facets_{purity,hisens}.seg
      Segmentation files for each FACETS mode.
"

argv <- commandArgs(trailing = TRUE)

if (any(c("-h", "--help") %in% argv)) {
  cat(usage)
  quit(status = 0)
}

keep_failed <- "--keep-failed" %in% argv

#
# Silence type_convert silently
#
type_convert<-function(x) {
  quietly(readr::type_convert)(x) %>% pluck("result")
}

# Load FACETS parameter columns configuration
param_cols <- readLines(file.path(get_script_dir(), "rsrc", "facetsParamCols")) |>
  str_trim() |>
  discard(~ .x == "")

#' Simplified wrapper for directory listing with recursion and regex
#' @param dir Directory path to search
#' @param pattern Regular expression pattern to match files
#' @return Character vector of matching file paths
dir_ls <- function(dir, pattern) {
  fs::dir_ls(dir, recurse = TRUE, regexp = pattern)
}

# Extract Project Information
# ===========================
# The project number is embedded in the output directory structure

project_no <- fs::dir_ls("out") %>% grep("/metrics",.,invert=T,value=T) %>% basename
sample_dir <- file.path("out", project_no, "somatic")

reports_dir <- "post/reports"
fs::dir_create(reports_dir)

facets_dir <- "post/plots/facets"
fs::dir_create(facets_dir)

script_dir <- get_script_dir()

# Quality Control: Identify Failed Samples
# =========================================
# Read individual FACETS QC files from each sample directory to identify
# samples that fail the sample filter. A sample passes if it passed FACETS QC,
# or if it failed QC but its dipLogR is close to 0. Failing samples are
# excluded from final outputs.

max_abs_diplogr <- 0.5

# Find all QC files across sample directories
facets_qc_files <- dir_ls(sample_dir, "\\.facets_qc\\.txt")

if (length(facets_qc_files) == 0) {
  cat("\nERROR: No FACETS QC files found in", sample_dir, "\n\n")
  quit(status = 1)
}

# Read and combine all QC files
qc_data <- map(
  facets_qc_files,
  ~ read_tsv(.x, col_types = cols(.default = "c"), show_col_types = FALSE),
  .progress = TRUE
) |>
  bind_rows() |>
  type_convert()

# Remove paths that are not useful for users
qc_data <- qc_data |>
  select(-path, -purity_run_prefix, -hisens_run_prefix)

# Extract samples that fail the filter: facets_qc || |dipLogR| < max_abs_diplogr
# A missing dipLogR does not rescue a sample that failed QC
failed_samples <- qc_data |>
  filter(!(facets_qc | coalesce(abs(dipLogR) < max_abs_diplogr, FALSE))) |>
  pull(tumor_sample_id)

message(
  "Found ", length(failed_samples), " samples that failed FACETS QC with ",
  "|dipLogR| >= ", max_abs_diplogr
)
if (length(failed_samples) > 0) {
  message("Failed samples: ", str_c(failed_samples, collapse = ", "))
}

# Optionally override the failed-sample filter. Setting failed_samples to NULL
# makes the downstream `filter(!sample %in% failed_samples)` calls a no-op, so
# every sample is retained in the output.
if (keep_failed) {
  message("--keep-failed set: retaining all samples (sample filter disabled)")
  failed_samples <- NULL
}

#' Process FACETS segmentation files
#'
#' This function handles the common pattern of reading, cleaning, and filtering
#' segmentation files from FACETS output
#'
#' @param file_pattern Regular expression pattern to match segmentation files
#' @param output_suffix Suffix for the output filename
#' @return Processed segmentation data frame, or NULL if no files found
process_segmentation_file <- function(file_pattern, output_suffix) {
  segmentation_files <- fs::dir_ls("out", recurse = TRUE, regexp = file_pattern)

  if (length(segmentation_files) == 0) {
    cat("\nERROR: No segmentation files found matching pattern:", file_pattern, "\n\n")
    return(NULL)
  }

  segmentation_data <- segmentation_files |>
    read_tsv(show_col_types = FALSE) |>
    # Exclude samples that failed QC
    filter(!(ID %in% failed_samples)) |>
    # Clean sample IDs by removing pipeline suffixes (everything after __)
    mutate(ID = str_remove(ID, "__.*"))

  if(nrow(segmentation_data)>0) {

    filter_tag <- if (keep_failed) "_NO_FILT_" else "_Filtered_"
    output_filename <- str_c("Proj_", project_no, filter_tag, output_suffix)
    write_tsv(segmentation_data, file.path(facets_dir, output_filename))

    message("Wrote ", nrow(segmentation_data), " segments to ", output_filename)
    return(segmentation_data)

  }

}

# Process Purity Mode Segmentation
# =================================
# FACETS purity mode uses a more conservative approach for copy number calling

segmentation_purity <- process_segmentation_file(
  "default_cohort/cna_purity_run_segmentation.seg",
  "facets_purity.seg"
)

# Process High Sensitivity Mode Segmentation
# ===========================================
# FACETS hisens mode is more sensitive and may detect smaller alterations

segmentation_hisens <- process_segmentation_file(
  "default_cohort/cna_hisens_run_segmentation.seg",
  "facets_hisens.seg"
)

# Collect Comprehensive Analysis Results for Excel Export
# =======================================================
# Gather run information, arm-level, and gene-level CNA data from cohort analysis

# Run information includes sample purity estimates and other QC metrics
run_info_files <- fs::dir_ls("out", recurse = 3,
                             regexp = "cohort_level/.*/cna_facets_run_info.txt")

if (length(run_info_files) == 0) {
  cat("\nERROR: No FACETS run info files found\n\n")
  quit(status = 1)
}

run_info_raw <- run_info_files |>
  map_dfr(~ read_tsv(.x, show_col_types = FALSE)) |>
  # Focus on purity-related metrics (the key FACETS parameter)
  filter(str_detect(Sample, "purity"))

# Extract FACETS parameters for documentation
facets_parameters <- run_info_raw |>
  select(all_of(param_cols)) |>
  slice(1) |>
  rename(version = Facets) |>
  gather(Param, Value)

# Prepare QC flags for joining
facets_qc_flags <- qc_data |>
  select(Sample = tumor_sample_id, facets_qc)

# Clean run info and add QC flags
run_info <- run_info_raw |>
  select(-all_of(param_cols)) |>
  mutate(Sample = str_remove(Sample, "_purity$")) |>
  left_join(facets_qc_flags, by = "Sample") |>
  select(Sample, facets_qc, everything())

# Arm-level copy number alterations (broad chromosomal changes)
arm_level_files <- fs::dir_ls("out", recurse = 3,
                              regexp = "cohort_level/.*/cna_armlevel.txt")

cna_arm_level <- if (length(arm_level_files) > 0) {
  arm_level_files |>
    map_dfr(~ read_tsv(.x, show_col_types = FALSE)) |>
    # Remove header row artifacts and ensure proper data types
    filter(sample != "sample") |>
    type_convert() |>
    filter(!sample %in% failed_samples) |>
    # Autosomes only: chrX (FACETS 23p/23q) cannot be called accurately
    # without sex info
    filter(!str_detect(arm, "^(23|24|X|Y)[pq]")) |>
    # Numeric chromosome order (1p, 1q, 2p, ..., 22q) within each sample
    arrange(
      sample,
      as.numeric(str_remove(arm, "[pq]$")),
      str_extract(arm, "[pq]$")
    )
} else {
  message("Warning: No arm-level CNA files found")
  tibble()
}

# Gene-level copy number alterations (focal changes affecting specific genes)
gene_level_files <- fs::dir_ls("out", recurse = 3,
                               regexp = "cohort_level/.*/cna_genelevel.txt")

cna_gene_level <- if (length(gene_level_files) > 0) {
  gene_level_files |>
    map_dfr(~ read_tsv(.x, show_col_types = FALSE)) |>
    filter(!sample %in% failed_samples)
} else {
  message("Warning: No gene-level CNA files found")
  tibble()
}

# Focal gene-level summary
# ========================
# One row per gene that lies on a segment of max_focal_seg_length or smaller
# in at least one sample, where the focal calls with tcn != 2 are all gains
# or all losses (see filter below). Autosomes only: chrX (FACETS chrom 23)
# cannot be called accurately without sex info.
#
# The gene-level files omit diploid calls, so every call counted below is a
# non-diploid call; diploid samples are not counted.
#   arm: chromosome arm of gene_start, from rsrc/centromeres_<genome>.tsv
#   samples_focal, n_focal: samples with a call on a focal segment
#   samples_all, n_all: samples with a call at the gene, any segment size
#   pct_loss (tcn < 2), pct_cnloh (tcn == 2), pct_amp (tcn > 2): all calls,
#     as a percentage of all samples in the cohort (after the sample
#     filter), so the three can sum to less than 100
#   cn_state_summary, tcn_summary: one entry per sample in samples_all
#     order; "+" marks a focal call

max_focal_seg_length <- 1e6

gene_level_focal <- if (nrow(cna_gene_level) > 0) {
  n_cohort <- qc_data |>
    filter(!tumor_sample_id %in% failed_samples) |>
    pull(tumor_sample_id) |>
    n_distinct()

  # p/q arm boundaries for the genome FACETS was run with
  genome <- facets_parameters |>
    filter(Param == "genome") |>
    pull(Value)
  centromeres <- read_tsv(
    file.path(script_dir, "rsrc", str_glue("centromeres_{genome}.tsv")),
    comment = "#",
    show_col_types = FALSE
  )

  cna_gene_level |>
    # Numeric chromosome order (1, 2, ..., 22); X and Y map to 23 and 24
    mutate(
      chrom_key = as.character(chrom) |>
        str_remove("^chr") |>
        str_replace_all(c("^X$" = "23", "^Y$" = "24")) |>
        as.numeric()
    ) |>
    filter(chrom_key <= 22) |>
    left_join(centromeres, by = c("chrom_key" = "chrom")) |>
    mutate(
      arm = str_c(chrom_key, if_else(gene_start < centromere, "p", "q")),
      sample = str_remove(sample, "__.*"),
      focal = seg_length <= max_focal_seg_length,
      focal_tag = if_else(focal, "+", "")
    ) |>
    arrange(sample) |>
    group_by(gene, arm, tsg, chrom, chrom_key, gene_start, gene_end) |>
    # Keep a gene only if it has at least one focal call with tcn != 2, and
    # all such calls agree in the sign of tcn - 2 (all gain or all loss).
    # Focal tcn == 2 (CNLOH) calls are ignored in the sign check.
    filter(n_distinct(sign(tcn - 2)[focal & tcn != 2]) == 1) |>
    summarize(
      samples_focal = str_c(sample[focal], collapse = ","),
      samples_all = str_c(sample, collapse = ","),
      n_focal = sum(focal),
      n_all = n(),
      pct_loss = round(100 * sum(tcn < 2) / n_cohort),
      pct_cnloh = round(100 * sum(tcn == 2) / n_cohort),
      pct_amp = round(100 * sum(tcn > 2) / n_cohort),
      cn_state_summary = str_c(cn_state, focal_tag, collapse = ";"),
      tcn_summary = str_c(tcn, focal_tag, collapse = ";"),
      .groups = "drop"
    ) |>
    arrange(chrom_key, gene_start, gene) |>
    select(
      gene, arm, samples_focal, samples_all, n_focal, n_all,
      pct_loss, pct_cnloh, pct_amp, cn_state_summary, tcn_summary,
      chrom, gene_start, gene_end, tsg
    )
} else {
  tibble()
}

# Generate Multi-Sheet Excel Report
# ==================================
# This consolidated report provides different views of the FACETS analysis:
# - runInfo: Sample-level metrics and purity estimates
# - armLevel: Chromosomal arm gains/losses across samples
# - geneLevelFocal: Genes on segments <= 1Mb, with cohort CN-state stats

excel_filename <- str_c(
  "Proj_", project_no, if (keep_failed) "_NO_FILT" else "", "_facets_v4.xlsx"
)

source(file.path(script_dir, "rsrc", "xlsx_legacy.R"))

write_xlsx_report(
  list(
    runInfo = run_info,
    armLevel = cna_arm_level,
    geneLevelFocal = gene_level_focal,
    facetsQC = qc_data,
    facetsParams = facets_parameters
  ),
  file.path(reports_dir, excel_filename)
)

message("Generated comprehensive Excel report: ", excel_filename)
message("  - runInfo sheet: ", nrow(run_info), " entries")
message("  - armLevel sheet: ", nrow(cna_arm_level), " entries")
message("  - geneLevelFocal sheet: ", nrow(gene_level_focal), " entries")
