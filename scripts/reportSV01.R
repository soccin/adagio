# Setup and dependencies
VERSION <- "v8"
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

#
# Excel formatting (openxlsx2; called with :: so nothing is attached or masked)
#

#' Excel number format for one column
#'
#' VAF columns are fractions and are shown as percentages; whole-number columns
#' get a thousands separator (genomic coordinates included); other numerics get
#' two decimals. Non-numeric columns get no format.
#'
#' @param col_name Column name
#' @param values Column values
#' @return Excel format code, or NA if the column needs none
excel_num_fmt <- function(col_name, values) {
  if (!is.numeric(values)) {
    return(NA_character_)
  }
  if (str_detect(col_name, "VAF")) {
    return("0.0%")
  }
  if (all(values == round(values), na.rm = TRUE)) {
    return("#,##0")
  }
  "0.00"
}

#' Column widths that fit their content, capped
#'
#' The cap matters: a single long CC/DGv annotation would otherwise stretch one
#' column past the width of the screen.
#'
#' @param tbl Table being written
#' @param max_width Widest column allowed, in characters
#' @return Numeric width per column
fit_col_widths <- function(tbl, max_width = 60) {
  header_width <- nchar(names(tbl)) * 1.2  # fudge for the bold header font
  # na.rm matters: nchar(NA_character_) is NA, not 2
  value_width <- map_dbl(tbl, \(x) max(nchar(as.character(x)), 0, na.rm = TRUE))
  pmin(pmax(header_width, value_width) + 2, max_width)
}

#' Add one table to the workbook as a reader-friendly sheet
#'
#' Bold wrapped header, frozen header row, fitted column widths, per-column
#' number formats.
#'
#' Excel cannot represent NaN/Inf, so both packages write them as error codes
#' (#VALUE!/#NUM!) -- the VAF divisions produce NaN whenever a caller had no
#' reads at all. Those become empty cells here instead. `na.strings = NULL`
#' leaves NA cells genuinely absent rather than openxlsx2's default #N/A or an
#' empty text cell, so ISBLANK works and numeric columns stay numeric.
#'
#' @param wb openxlsx2 workbook
#' @param sheet_name Name for the new worksheet
#' @param tbl Table to write
#' @return The workbook with the sheet added
add_report_sheet <- function(wb, sheet_name, tbl) {
  tbl <- tbl |>
    mutate(across(where(is.numeric), \(x) replace(x, !is.finite(x), NA)))

  header <- openxlsx2::wb_dims(rows = 1, cols = seq_along(tbl))

  wb <- wb |>
    openxlsx2::wb_add_worksheet(sheet_name) |>
    openxlsx2::wb_add_data(x = tbl, na.strings = NULL) |>
    openxlsx2::wb_add_font(dims = header, bold = "1") |>
    openxlsx2::wb_add_cell_style(
      dims = header,
      wrap_text = TRUE,
      horizontal = "left"
    ) |>
    openxlsx2::wb_freeze_pane(first_active_row = 2) |>
    openxlsx2::wb_set_col_widths(
      cols = seq_along(tbl),
      widths = fit_col_widths(tbl)
    )

  # One call per distinct format, covering all its columns at once: openxlsx2
  # registers a new format entry on every call and Excel only tolerates ~200
  # per workbook, which per-column calls would exceed on the wide SVEvents sheet
  if (nrow(tbl) > 0) {
    data_rows <- 1 + seq_len(nrow(tbl))
    col_fmts <- map2_chr(names(tbl), tbl, excel_num_fmt)

    for (fmt in unique(na.omit(col_fmts))) {
      dims <- which(col_fmts == fmt) |>
        map_chr(\(j) openxlsx2::wb_dims(rows = data_rows, cols = j)) |>
        str_c(collapse = ",")
      wb <- openxlsx2::wb_add_numfmt(wb, dims = dims, numfmt = fmt)
    }
  }

  wb
}

#' Write the report sheets to a formatted xlsx file
#'
#' @param sheets Named list of tables, one worksheet each
#' @param path Output .xlsx path
#' @return Invisibly, path
write_report_workbook <- function(sheets, path) {
  wb <- openxlsx2::wb_workbook()
  for (sheet_name in names(sheets)) {
    wb <- add_report_sheet(wb, sheet_name, sheets[[sheet_name]])
  }
  openxlsx2::wb_save(wb, path, overwrite = TRUE)
  invisible(path)
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

  write_report_workbook(
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
