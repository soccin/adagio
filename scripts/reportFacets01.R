# FACETS Report Generation Script
# ==============================
# This script processes FACETS copy number analysis results and generates
# consolidated reports in both TSV and Excel formats.
#
# Key outputs:
# - Individual segmentation files (purity and hisens modes)
# - Multi-sheet Excel workbook with run info, arm-level, and gene-level CNAs

# Helper Functions
# ================

# Simplified wrapper for directory listing with recursion and regex
dir_ls <- function(dir, pattern) {
  fs::dir_ls(dir, recurse = TRUE, regexp = pattern)
}

library(tidyverse)
library(readxl)
library(openxlsx)

# Extract Project Information
# ===========================
# The project number is embedded in the output directory structure

project_no <- basename(fs::dir_ls("out"))
sample_dir <- file.path("out", project_no, "somatic")

# Quality Control: Identify Failed Samples
# =========================================
# Read individual FACETS QC files from each sample directory to identify
# samples that failed quality control. These samples will be excluded from
# final outputs to ensure reliable results.

# Find all QC files across sample directories
facets_qc_files <- dir_ls(sample_dir, "\\.facets_qc\\.txt")

# Read and combine all QC files
qc_data <- map(
  facets_qc_files,
  ~read_tsv(.x, col_types = cols(.default = "c"), show_col_types = FALSE),
  .progress = TRUE
) %>%
  bind_rows() %>%
  type_convert()

# Extract samples that failed QC (facets_qc == FALSE)
failed_samples <- qc_data %>%
  filter(!facets_qc) %>%
  pull(tumor_sample_id)

message("Found ", length(failed_samples), " samples that failed FACETS QC")
if (length(failed_samples) > 0) {
  message("Failed samples: ", str_c(failed_samples, collapse = ", "))
}

# Helper function to process segmentation files
# =============================================
# This function handles the common pattern of reading, cleaning, and filtering
# segmentation files from FACETS output

process_segmentation_file <- function(file_pattern, output_suffix) {
  seg_file <- fs::dir_ls("out", recurse = TRUE, regexp = file_pattern)

  if (length(seg_file) == 0) {
    warning("No files found matching pattern: ", file_pattern)
    return(NULL)
  }

  seg <- seg_file %>%
    read_tsv(show_col_types = FALSE) %>%
    # Clean sample IDs by removing pipeline suffixes (everything after __)
    mutate(ID = str_remove(ID, "__.*")) %>%
    # Exclude samples that failed QC
    filter(!(ID %in% failed_samples))

  output_file <- str_c("Proj_", project_no, "_", output_suffix)
  write_tsv(seg, output_file)

  message("Wrote ", nrow(seg), " segments to ", output_file)
  return(seg)
}

# Process Purity Mode Segmentation
# =================================
# FACETS purity mode uses a more conservative approach for copy number calling

seg_purity <- process_segmentation_file(
  "default_cohort/cna_purity_run_segmentation.seg",
  "facets_purity.seg"
)

# Process High Sensitivity Mode Segmentation
# ===========================================
# FACETS hisens mode is more sensitive and may detect smaller alterations

seg_hisens <- process_segmentation_file(
  "default_cohort/cna_hisens_run_segmentation.seg",
  "facets_hisens.seg"
)

# Collect Comprehensive Analysis Results for Excel Export
# =======================================================
# Gather run information, arm-level, and gene-level CNA data from cohort analysis

# Run information includes sample purity estimates and other QC metrics
run_info <- fs::dir_ls("out", recurse = 3,
                       regexp = "cohort_level/.*/cna_facets_run_info.txt") %>%
  map_dfr(~read_tsv(.x, show_col_types = FALSE)) %>%
  # Focus on purity-related metrics (the key FACETS parameter)
  filter(str_detect(Sample, "purity"))

# Arm-level copy number alterations (broad chromosomal changes)
cna_armlevel <- fs::dir_ls("out", recurse = 3,
                           regexp = "cohort_level/.*/cna_armlevel.txt") %>%
  map_dfr(~read_tsv(.x, show_col_types = FALSE)) %>%
  # Remove header row artifacts and ensure proper data types
  filter(sample != "sample") %>%
  type_convert() %>%
  filter(!sample %in% failed_samples)

# Gene-level copy number alterations (focal changes affecting specific genes)
cna_genelevel <- fs::dir_ls("out", recurse = 3,
                            regexp = "cohort_level/.*/cna_genelevel.txt") %>%
  map_dfr(~read_tsv(.x, show_col_types = FALSE)) %>%
  filter(!sample %in% failed_samples)

# Generate Multi-Sheet Excel Report
# ==================================
# This consolidated report provides different views of the FACETS analysis:
# - runInfo: Sample-level metrics and purity estimates
# - armLevel: Chromosomal arm gains/losses across samples
# - geneLevel: Gene-specific copy number changes

excel_filename <- str_c("Proj_", project_no, "_CNV_Facets_v2.xlsx")

write.xlsx(
  list(
    runInfo = run_info,
    armLevel = cna_armlevel,
    geneLevel = cna_genelevel
  ),
  excel_filename
)

message("Generated comprehensive Excel report: ", excel_filename)
message("  - runInfo sheet: ", nrow(run_info), " entries")
message("  - armLevel sheet: ", nrow(cna_armlevel), " entries")
message("  - geneLevel sheet: ", nrow(cna_genelevel), " entries")
