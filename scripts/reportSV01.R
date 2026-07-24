# Setup and dependencies
VERSION <- "v7"
PROOT <- get_script_dir()
source(file.path(PROOT, "rsrc/read_tempo_sv.R"))
source(file.path(PROOT, "rsrc/add_sv_scores.R"))
source(file.path(PROOT, "rsrc/read_pairing.R"))
argv <- commandArgs(trailing = TRUE)

suppressPackageStartupMessages(require(tidyverse))

#' Convert column types without the readr guessing messages
#'
#' @param tbl Table with character columns to convert
#' @return Table with converted column types
quiet_type_convert <- function(tbl) {
  quietly(readr::type_convert)(tbl) |>
    pluck("result")
}

#' Orientation-independent gene-pair label for an SV
#'
#' Genes are sorted so that A/B and B/A give the same label. An unannotated
#' breakpoint is written as "." rather than dropped; SVs with neither end
#' annotated get NA so they are not all pooled into one pseudo-pair.
#'
#' @param gene1,gene2 Gene names at each breakpoint (NA or "" if unannotated)
#' @return Character vector of "GENEA::GENEB" labels, NA when both are missing
make_gene_pair <- function(gene1, gene2) {
  g1 <- na_if(gene1, "")
  g2 <- na_if(gene2, "")
  pair <- str_c(
    pmin(replace_na(g1, "."), replace_na(g2, ".")),
    pmax(replace_na(g1, "."), replace_na(g2, ".")),
    sep = "::"
  )
  if_else(is.na(g1) & is.na(g2), NA_character_, pair)
}

# Read all SV BEDPE files and combine
# Using .final.bedpe instead of clustered output which fails on unmatched samples
sv_files <- fs::dir_ls("out", recur = TRUE, regex = "\\.final\\.bedpe$")
sv_data <- map(sv_files, read_tempo_sv_somatic, .progress = TRUE) |>
  bind_rows()

# Get full list of tumors from pairing file
# Handles cases where samples have no SVs
tumors <- read_pairing() |>
  pull(TUMOR_ID)

has_svs <- nrow(sv_data) > 0

if (!has_svs) {
  cat("\nNo structure variants found\n\n")
} else {

  # Remove unnecessary columns
  sv_data <- sv_data |>
    select(-INFO_A, -INFO_B, -FORMAT, -TUMOR, -NORMAL)

  # Reorder columns: core info, then AD/PE/SR/PR/PS, then annotations
  sv_data <- sv_data |>
    select(
      1:CC_Chr_Band,
      matches("_(AD|PE|SR|PR|PS)$"),
      matches("^CC|^DGv"),
      matches("CONSENSUS"),
      everything()
    ) |>
    quiet_type_convert()

  # Calculate VAF for each caller
  sv_data <- sv_data |>
    mutate(
      # Delly VAFs
      t_delly_SpanVAF = t_delly_DV / (t_delly_DV + t_delly_DR),
      t_delly_JuncVAF = t_delly_RV / (t_delly_RV + t_delly_RR),
      n_delly_SpanVAF = n_delly_DV / (n_delly_DV + n_delly_DR),
      n_delly_JuncVAF = n_delly_RV / (n_delly_RV + n_delly_RR),
      # Svaba VAFs
      t_svaba_VAF = pmin(t_svaba_AD / t_svaba_DP, 1),
      n_svaba_VAF = pmin(n_svaba_AD / n_svaba_DP, 1)
    ) |>
    # Manta split reads need parsing
    separate(t_manta_SR, c("t_manta_SRR", "t_manta_SRV"), remove = FALSE) |>
    mutate(
      t_manta_JuncVAF = as.numeric(t_manta_SRV) /
        (as.numeric(t_manta_SRV) + as.numeric(t_manta_SRR))
    )

  # Select final columns for output
  sv_events <- sv_data |>
    select(
      1:CC_Chr_Band,
      matches("VAF"),
      matches("_(AD|PE|SR|PR|PS|DR|DV|RR|RV)$"),
      matches("^CC|^DGv"),
      matches("CONSENSUS"),
      NORMAL_ID,
      UUID
    )

  # Score events and label each one with its orientation-independent gene pair
  sv_events <- add_sv_scores(sv_events) |>
    select(
      TUMOR_ID:repeat.site2,
      SCORE,
      SCORE_SPAN,
      SCORE_SPLIT,
      everything()
    ) |>
    arrange(desc(SCORE)) |>
    mutate(genePair = make_gene_pair(gene1, gene2))

  # Load column descriptions
  col_desc <- read_csv(
    file.path(PROOT, "rsrc/svColTypeDescriptions.csv"),
    show_col_types = FALSE,
    progress = FALSE
  )

  # Count SVs per sample; zero-fill happens after the join to the pairing
  # list so tumors with no BEDPE file also report 0 rather than NA
  sv_counts <- tibble(
    TUMOR_ID = basename(sv_files) |> str_remove("__.*")
  ) |>
    left_join(count(sv_events, TUMOR_ID), by = join_by(TUMOR_ID)) |>
    rename(NumSVs = n)

  sample_data <- tibble(TUMOR_ID = tumors) |>
    left_join(sv_counts, by = join_by(TUMOR_ID)) |>
    mutate(NumSVs = replace_na(NumSVs, 0))

  # Recurrent gene pairs: those hit in more than one sample
  sv_freq <- sv_events |>
    filter(!is.na(genePair)) |>
    distinct(TUMOR_ID, genePair) |>
    summarize(
      N = n(),
      Samples = str_c(sort(TUMOR_ID), collapse = "; "),
      .by = genePair
    ) |>
    filter(N > 1) |>
    arrange(desc(N))

}

# Determine project number and output file name
proj_no <- fs::dir_ls("out") |>
  str_subset("/metrics", negate = TRUE) |>
  basename()

if (!str_detect(proj_no, "^Proj_")) {
  proj_no <- cc("Proj", proj_no)
}

report_file <- cc(proj_no, "SV_Report01", paste0(VERSION, ".xlsx"))
report_dir <- "post/reports"
fs::dir_create(report_dir)

if (has_svs) {

  write_xlsx(
    list(
      SampleData = sample_data,
      SVFreq = sv_freq,
      SVEvents = sv_events,
      ColDescriptions = col_desc
    ),
    file.path(report_dir, report_file)
  )

} else {
  write(
    "\nThere are no SV's\n",
    file.path(report_dir, "README_NoSVs.txt")
  )
}
