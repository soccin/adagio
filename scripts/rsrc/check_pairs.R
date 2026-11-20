suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
  library(readr)
  library(stringr)
  library(tibble)
})

#' Per-pair output file of each Tempo workflow
#'
#' Paths are relative to the project output folder (out/<PROJECT_ID>).
#' {pair} is <TUMOR>__<NORMAL>, {normal} is the normal sample ID. A pair
#' has finished a workflow when every file listed for that workflow
#' exists. mutsig, msisensor and lohhla write no per-pair file that can
#' be checked, so they are not listed.
pair_output_files <- tribble(
  ~workflow, ~template,
  "snv",     "somatic/{pair}/combined_mutations/{pair}.somatic.final.maf",
  "facets",  "somatic/{pair}/facets/{pair}/{pair}.facets_qc.txt",
  "qc",      "somatic/{pair}/conpair/{pair}.concordance.txt",
  "qc",      "somatic/{pair}/conpair/{pair}.contamination.txt",
  "sv",      "somatic/{pair}/combined_svs/{pair}.final.bedpe",
  "germsnv", "germline/{normal}/combined_mutations/{pair}.germline.final.maf",
  "germsv",  "germline/{normal}/combined_svs/{normal}.final.bedpe"
)

#' Find pairs that are missing a workflow's output
#'
#' Tempo can drop a pair and still finish: a task that fails on every
#' attempt is ignored (errorStrategy in conf/iris.config), and pairs
#' whose samples are not in the mapping are removed with no message.
#' This compares the pairing table with the files in the output folder.
#'
#' @param pairing Tibble with NORMAL_ID and TUMOR_ID columns
#' @param odir Project output folder (out/<PROJECT_ID>)
#' @param workflows Character vector of Tempo workflow names
#' @return Tibble with TUMOR_ID, NORMAL_ID, workflow and file (relative
#'   to odir) for every expected file that does not exist
find_missing_outputs <- function(pairing, odir, workflows) {

  pairing |>
    distinct(TUMOR_ID, NORMAL_ID) |>
    cross_join(filter(pair_output_files, workflow %in% workflows)) |>
    mutate(
      file = pmap_chr(
        list(template, TUMOR_ID, NORMAL_ID),
        \(tmpl, tumor, normal) str_glue(tmpl, pair = str_c(tumor, "__", normal), normal = normal)
      )
    ) |>
    filter(!fs::file_exists(file.path(odir, file))) |>
    select(TUMOR_ID, NORMAL_ID, workflow, file)

}

#' Workflows in the list that have no per-pair file to check
#'
#' @param workflows Character vector of Tempo workflow names
#' @return The workflows that find_missing_outputs() does not check
unchecked_workflows <- function(workflows) {
  setdiff(workflows, pair_output_files$workflow)
}

#' Pairs missing a workflow's output, for the reports
#'
#' Reads the pairing file of the run (read_pairing(), so source
#' rsrc/read_pairing.R too), checks it against the project output folder
#' that holds runlog/cmd.sh.log, and prints a warning that names each
#' missing pair.
#'
#' @param workflows Workflows the report is built from
#' @param out_dir Pipeline output directory (default "out")
#' @return Tibble from find_missing_outputs(); zero rows if none missing
report_missing_pairs <- function(workflows, out_dir = "out") {

  cmd_log <- fs::dir_ls(out_dir, recurse = TRUE, regexp = "runlog/cmd.sh.log$")

  if (length(cmd_log) != 1) {
    stop(str_glue(
      "\n\nreport_missing_pairs: expected one runlog/cmd.sh.log under ",
      "{out_dir}, found {length(cmd_log)}\n\n"
    ), call. = FALSE)
  }

  odir <- fs::path_dir(fs::path_dir(cmd_log))
  missing <- find_missing_outputs(read_pairing(out_dir), odir, workflows)

  if (nrow(missing) > 0) {
    warning_lines <- str_glue(
      "  {missing$TUMOR_ID}__{missing$NORMAL_ID}  {missing$workflow}  {missing$file}"
    )
    message(
      "\nWARNING: ", n_distinct(missing$TUMOR_ID, missing$NORMAL_ID),
      " pair(s) in the pairing file are missing output; they are listed\n",
      "in the MissingPairs part of this report:\n\n",
      str_c(warning_lines, collapse = "\n"), "\n"
    )
  }

  missing

}
