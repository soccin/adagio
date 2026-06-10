suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
  library(readr)
  library(stringr)
})

#' Read the Tempo pairing table for this project
#'
#' The run scripts record the full nextflow command in
#' out/*/runlog/cmd.sh.log and copy the pairing file into the same
#' runlog directory. The --pairing argument in that log is the
#' authoritative record of which pairing file was used, so parse it
#' from there rather than guessing by filename. Prefer the runlog
#' copy (it survives moves of the original); fall back to the
#' recorded path itself.
#'
#' @param out_dir Pipeline output directory (default "out")
#' @return Tibble with NORMAL_ID and TUMOR_ID columns
read_pairing <- function(out_dir = "out") {

  cmd_logs <- fs::dir_ls(out_dir, recurse = TRUE, regexp = "runlog/cmd.sh.log$")

  if (length(cmd_logs) == 0) {
    stop(str_glue(
      "\n\nread_pairing: no runlog/cmd.sh.log found under {out_dir}\n",
      "Has the pipeline been run from this directory?\n\n"
    ), call. = FALSE)
  }

  pairing_file_from_log <- function(log) {

    pairing_path <- read_file(log) |>
      str_extract("--pairing[= ]+(\\S+)", group = 1)

    if (is.na(pairing_path)) {
      stop(str_glue(
        "\n\nread_pairing: no --pairing argument found in\n  {log}\n\n"
      ), call. = FALSE)
    }

    runlog_copy <- file.path(dirname(log), basename(pairing_path))
    candidates <- c(runlog_copy, pairing_path)
    found <- candidates[fs::file_exists(candidates)]

    if (length(found) == 0) {
      stop(str_glue(
        "\n\nread_pairing: pairing file from {log} not found; tried:\n",
        str_c("  ", candidates, collapse = "\n"),
        "\n\n"
      ), call. = FALSE)
    }

    found[1]

  }

  read_one <- function(pfile) {

    pairing <- read_tsv(pfile, show_col_types = FALSE, progress = FALSE)

    missing_cols <- setdiff(c("NORMAL_ID", "TUMOR_ID"), names(pairing))
    if (length(missing_cols) > 0) {
      stop(str_glue(
        "\n\nread_pairing: {pfile}\n",
        "is missing required column(s): ",
        str_c(missing_cols, collapse = ", "),
        "\n\n"
      ), call. = FALSE)
    }

    pairing

  }

  cmd_logs |>
    map_chr(pairing_file_from_log) |>
    unique() |>
    map(read_one) |>
    bind_rows() |>
    select(NORMAL_ID, TUMOR_ID) |>
    distinct()

}
