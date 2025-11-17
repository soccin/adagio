suppressPackageStartupMessages(library(tidyverse))

#' Find metrics files by pattern
#'
#' @param pattern Regex pattern to match file names (e.g., "wgs.txt", "asm.txt")
#' @return Character vector of file paths
find_metrics_files <- function(pattern) {
  fs::dir_ls(".", recur = 2, regex = "out/metrics") |>
    fs::dir_ls(recur = TRUE, regex = pattern)
}

#' Read and process metrics files
#'
#' @param files Character vector of file paths to read
#' @param n_max Maximum number of rows to read from each file
#' @param select_cols Character vector of column names to select
#' @param filter_fn Optional function to filter rows (default: NULL)
#' @return Tibble with processed metrics
read_metrics <- function(files, n_max, select_cols, filter_fn = NULL) {
  stats <- map(
    files,
    read_tsv,
    comment = "#",
    n_max = n_max,
    col_types = cols(.default = "c"),
    progress = FALSE
  ) |>
    bind_rows(.id = "sample") |>
    mutate(sample = basename(dirname(sample))) |>
    janitor::clean_names()

  if (!is.null(filter_fn)) {
    stats <- filter_fn(stats)
  }

  select(stats, sample, all_of(select_cols))
}

# Extract WGS coverage statistics
wgs_files <- find_metrics_files("wgs.txt")

if(len(wgs_files)==0) {
  cat("
  Can not find any WGS stats file.
  Did you generate them (SMap/bin/collect...)
\n\n")
  quit()
}

wgs_stats <- read_metrics(
  wgs_files,
  n_max = 1,
  select_cols = c("mean_coverage", "pct_20x", "pct_60x")
)

# Extract alignment statistics for paired reads
asm_files <- find_metrics_files("asm.txt")
asm_stats <- read_metrics(
  asm_files,
  n_max = 3,
  select_cols = c(
    "total_reads",
    "pct_pf_reads_aligned",
    "mean_read_length",
    "pct_reads_aligned_in_pairs",
    "strand_balance",
    "pct_chimeras",
    "pct_softclip"
  ),
  filter_fn = \(x) filter(x, category == "PAIR")
)

# Combine WGS and alignment statistics
stats <- full_join(wgs_stats, asm_stats, by = join_by(sample))
