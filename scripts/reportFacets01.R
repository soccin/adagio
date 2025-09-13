# FACETS Report Generation Script
# ==============================
# This script processes FACETS copy number analysis results and generates
# consolidated reports in both TSV and Excel formats.
#
# Key outputs:
# - Individual segmentation files (purity and hisens modes)
# - Multi-sheet Excel workbook with run info, arm-level, and gene-level CNAs

library(tidyverse)
library(readxl)
library(openxlsx)

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

project_no <- basename(fs::dir_ls("out"))
sample_dir <- file.path("out", project_no, "somatic")

reports_dir <- "post/reports"
fs::dir_create(reports_dir)

script_dir <- get_script_dir()

# Quality Control: Identify Failed Samples
# =========================================
# Read individual FACETS QC files from each sample directory to identify
# samples that failed quality control. These samples will be excluded from
# final outputs to ensure reliable results.

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

# Extract samples that failed QC (facets_qc == FALSE)
failed_samples <- qc_data |>
  filter(!facets_qc) |>
  pull(tumor_sample_id)

message("Found ", length(failed_samples), " samples that failed FACETS QC")
if (length(failed_samples) > 0) {
  message("Failed samples: ", str_c(failed_samples, collapse = ", "))
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
    # Clean sample IDs by removing pipeline suffixes (everything after __)
    mutate(ID = str_remove(ID, "__.*")) |>
    # Exclude samples that failed QC
    filter(!(ID %in% failed_samples))

  output_filename <- str_c("Proj_", project_no, "_Filtered_", output_suffix)
  write_tsv(segmentation_data, file.path(reports_dir, output_filename))

  message("Wrote ", nrow(segmentation_data), " segments to ", output_filename)
  return(segmentation_data)
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
    filter(!sample %in% failed_samples)
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

# Generate Multi-Sheet Excel Report
# ==================================
# This consolidated report provides different views of the FACETS analysis:
# - runInfo: Sample-level metrics and purity estimates
# - armLevel: Chromosomal arm gains/losses across samples
# - geneLevel: Gene-specific copy number changes

excel_filename <- str_c("Proj_", project_no, "_facets_v3.xlsx")

write.xlsx(
  list(
    runInfo = run_info,
    armLevel = cna_arm_level,
    geneLevel = cna_gene_level,
    facetsQC = qc_data,
    facetsParams = facets_parameters
  ),
  file.path(reports_dir, excel_filename)
)

message("Generated comprehensive Excel report: ", excel_filename)
message("  - runInfo sheet: ", nrow(run_info), " entries")
message("  - armLevel sheet: ", nrow(cna_arm_level), " entries")
message("  - geneLevel sheet: ", nrow(cna_gene_level), " entries")
