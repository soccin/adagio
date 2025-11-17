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

if (len(wgs_files) == 0) {
  cat("\nERROR: Cannot find any WGS stats files.\n")
  cat("Did you generate them (SMap/bin/collect...)?\n\n")
  quit(status = 1)
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

# Combine and convert data types
stats <- full_join(wgs_stats, asm_stats) |>
  mutate(sample = ifelse(grepl("WGSCtrl", sample), "WGSCtrl", sample)) |>
  quietly(readr::type_convert)() %>%
  pluck("result")

# Create visualization
plot_stats <- stats |>
  mutate(total_reads = total_reads / 1e9) |>
  rename(total_reads_Gb = total_reads) |>
  gather(metric, value, -sample) |>
  mutate(value = ifelse(grepl("^pct", metric), value * 100, value)) |>
  ggplot(aes(sample, value)) +
    theme_light(14) +
    geom_col() +
    facet_wrap(~metric, scale = "free_x") +
    coord_flip() +
    xlab(NULL) +
    ylab(NULL)

# Determine output paths
proj_no <- basename(fs::dir_ls("out"))
if (!grepl("^Proj_", proj_no)) {
  proj_no <- cc("Proj", proj_no)
}

output_file <- cc(proj_no, "WGSStats", "v1.xlsx")
output_dir <- "post/reports"
fs::dir_create(output_dir)

# Write outputs
write_xlsx(stats, file.path(output_dir, output_file))
pdf(
  file = file.path(output_dir, gsub(".xlsx", ".pdf", output_file)),
  width = 11,
  height = 8.5
)
print(plot_stats)
invisible(dev.off())

