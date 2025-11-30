#!/usr/bin/env Rscript

# Compute aggregate depth metrics from TEMPO SV output
# Author: Claude Code
# Date: 2025-11-29
#
# Takes tempoSVOutput.csv and creates tempoSVDepth.csv with:
#   - Columns A-T (original identifiers and annotations)
#   - Aggregate depth metrics (MANTA-only, MAX, MEDIAN)
#
# Key insight: Different callers count the SAME reads, so we cannot sum.
# Instead, we use MAX (most sensitive) or MEDIAN (central tendency).

library(tidyverse)

# Helper function to extract ALT count from MANTA's "REF,ALT" format
extract_alt <- function(x) {
  if (is.na(x) || x == "NA" || x == "") {
    return(NA_real_)
  }

  # Handle quoted strings
  x <- gsub('"', '', x)

  # Split on comma and take second element
  parts <- strsplit(as.character(x), ",")[[1]]
  if (length(parts) != 2) {
    return(NA_real_)
  }

  alt <- suppressWarnings(as.numeric(parts[2]))
  return(alt)
}

# Vectorized version
extract_alt_vec <- function(x) {
  sapply(x, extract_alt)
}

# Read input file
cat("Reading tempoSVOutput.csv...\n")
df <- read.csv("tempoSVOutput.csv", stringsAsFactors = FALSE, na.strings = c("NA", ""))

cat(sprintf("Loaded %d variants\n", nrow(df)))

# Select columns A-T (1-20)
cat("Selecting columns A-T (1-20)...\n")
output <- df[, 1:20]

# Column indices (1-based in R)
# Column 30 (AD): t_manta_PR
# Column 31 (AE): t_manta_SR
# Column 32 (AF): t_svaba_AD
# Column 33 (AG): t_svaba_SR
# Column 39 (AM): t_delly_DV
# Column 41 (AO): t_delly_RV
# Column 42 (AP): t_svaba_DR

cat("Extracting ALT counts from MANTA fields...\n")

# Extract MANTA ALT counts (from "REF,ALT" format)
manta_pr_alt <- extract_alt_vec(df[[30]])  # t_manta_PR
manta_sr_alt <- extract_alt_vec(df[[31]])  # t_manta_SR

cat("Computing aggregate metrics...\n")

# Get individual caller counts
delly_paired <- as.numeric(df[[39]])  # t_delly_DV (column AM)
delly_split <- as.numeric(df[[41]])   # t_delly_RV (column AO)
svaba_paired <- as.numeric(df[[42]])  # t_svaba_DR (column AP)
svaba_split <- as.numeric(df[[33]])   # t_svaba_SR (column AG)
svaba_total <- as.numeric(df[[32]])   # t_svaba_AD (column AF)

# APPROACH 1: MANTA counts (cleanest, highest quality MAPQ>=30)
output$manta_paired_reads <- manta_pr_alt
output$manta_split_reads <- manta_sr_alt

# APPROACH 2: Maximum across callers (most sensitive detection)
output$max_paired_reads <- pmax(delly_paired, manta_pr_alt, svaba_paired, na.rm = TRUE)
output$max_split_reads <- pmax(delly_split, manta_sr_alt, svaba_split, na.rm = TRUE)

# APPROACH 3: Median across callers (central tendency)
# Note: Using rowMedians would require matrixStats package, so using apply
paired_matrix <- cbind(delly_paired, manta_pr_alt, svaba_paired)
split_matrix <- cbind(delly_split, manta_sr_alt, svaba_split)

output$median_paired_reads <- apply(paired_matrix, 1, function(x) median(x, na.rm = TRUE))
output$median_split_reads <- apply(split_matrix, 1, function(x) median(x, na.rm = TRUE))

# Handle cases where all values are NA (median returns Inf/-Inf)
output$median_paired_reads[is.infinite(output$median_paired_reads)] <- NA
output$median_split_reads[is.infinite(output$median_split_reads)] <- NA

# Total evidence (max approach)
output$total_max_reads <- output$max_paired_reads + output$max_split_reads

# Evidence type diversity (both PE and SR present?)
output$has_paired_evidence <- !is.na(output$max_paired_reads) & output$max_paired_reads > 0
output$has_split_evidence <- !is.na(output$max_split_reads) & output$max_split_reads > 0
output$multi_evidence_type <- output$has_paired_evidence & output$has_split_evidence

# Agreement score: how many callers see >= 3 split reads?
delly_sees_split <- !is.na(delly_split) & delly_split >= 3
manta_sees_split <- !is.na(manta_sr_alt) & manta_sr_alt >= 3
svaba_sees_split <- !is.na(svaba_split) & svaba_split >= 3

output$callers_with_3plus_split <- delly_sees_split + manta_sees_split + svaba_sees_split

# Agreement score: how many callers see >= 5 paired reads?
delly_sees_paired <- !is.na(delly_paired) & delly_paired >= 5
manta_sees_paired <- !is.na(manta_pr_alt) & manta_pr_alt >= 5
svaba_sees_paired <- !is.na(svaba_paired) & svaba_paired >= 5

output$callers_with_5plus_paired <- delly_sees_paired + manta_sees_paired + svaba_sees_paired

# Quality flag: meets recommended thresholds
output$meets_split_threshold <- !is.na(output$max_split_reads) & output$max_split_reads >= 3
output$meets_paired_threshold <- !is.na(output$max_paired_reads) & output$max_paired_reads >= 5

# Overall quality flag
output$high_quality_evidence <- output$meets_split_threshold &
                                output$meets_paired_threshold &
                                output$multi_evidence_type &
                                df[[19]] >= 2  # NumCallersPass >= 2 (column S)

# Add individual caller counts for reference
output$delly_paired <- delly_paired
output$delly_split <- delly_split
output$manta_paired <- manta_pr_alt
output$manta_split <- manta_sr_alt
output$svaba_paired <- svaba_paired
output$svaba_split <- svaba_split
output$svaba_total <- svaba_total

# Summary statistics
cat("\nSummary of aggregate metrics:\n")
cat(sprintf("  Variants with MANTA split reads: %d (%.1f%%)\n",
            sum(!is.na(output$manta_split_reads)),
            100 * mean(!is.na(output$manta_split_reads))))

cat(sprintf("  Variants meeting split threshold (>=3): %d (%.1f%%)\n",
            sum(output$meets_split_threshold, na.rm = TRUE),
            100 * mean(output$meets_split_threshold, na.rm = TRUE)))

cat(sprintf("  Variants meeting paired threshold (>=5): %d (%.1f%%)\n",
            sum(output$meets_paired_threshold, na.rm = TRUE),
            100 * mean(output$meets_paired_threshold, na.rm = TRUE)))

cat(sprintf("  Variants with multi-evidence type: %d (%.1f%%)\n",
            sum(output$multi_evidence_type, na.rm = TRUE),
            100 * mean(output$multi_evidence_type, na.rm = TRUE)))

cat(sprintf("  High quality variants (all criteria met): %d (%.1f%%)\n",
            sum(output$high_quality_evidence, na.rm = TRUE),
            100 * mean(output$high_quality_evidence, na.rm = TRUE)))

cat(sprintf("\nMedian max_split_reads: %.1f\n", median(output$max_split_reads, na.rm = TRUE)))
cat(sprintf("Median max_paired_reads: %.1f\n", median(output$max_paired_reads, na.rm = TRUE)))

# Write output
cat("\nWriting tempoSVDepth.csv...\n")
write.csv(output, "tempoSVDepth.csv", row.names = FALSE, na = "")

cat(sprintf("\nDone! Output written to tempoSVDepth.csv\n"))
cat(sprintf("  Input rows: %d\n", nrow(df)))
cat(sprintf("  Output rows: %d\n", nrow(output)))
cat(sprintf("  Output columns: %d\n", ncol(output)))

# Print column names for reference
cat("\nNew depth metric columns added:\n")
new_cols <- names(output)[21:ncol(output)]
for (i in seq_along(new_cols)) {
  cat(sprintf("  %2d. %s\n", 20 + i, new_cols[i]))
}

cat("\nRecommended columns for analysis:\n")
cat("  - manta_split_reads: Simplest, highest quality (MAPQ>=30)\n")
cat("  - manta_paired_reads: Simplest, highest quality\n")
cat("  - max_split_reads: Most sensitive detection\n")
cat("  - max_paired_reads: Most sensitive detection\n")
cat("  - high_quality_evidence: Boolean filter for high-confidence variants\n")
cat("  - NumCallersPass (column 19): Already in original data\n")
