#
# Check that every pair in the pairing file has the output of each
# workflow of the run. Run by runTempoWESCohort.sh and runTempoWGSBam.sh
# after nextflow finishes, because Tempo can drop a pair and still
# finish (see rsrc/check_pairs.R).
#
# Prints the result and writes it to <ODIR>/runlog/pair_check.txt.
# Exit status: 0 if every pair has every checked output, 3 if not.
#

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(stringr)
})

argv <- commandArgs(trailingOnly = TRUE)

if (length(argv) < 3) {
  cat("\n   usage: checkPairOutputs.R PAIRING.tsv ODIR WORKFLOWS\n\n")
  cat("   PAIRING.tsv  Tempo pairing file (NORMAL_ID, TUMOR_ID)\n")
  cat("   ODIR         Project output folder, out/<PROJECT_ID>\n")
  cat("   WORKFLOWS    Comma-separated Tempo workflows, e.g. snv,qc,facets\n\n")
  quit(status = 1)
}

pairing_file <- argv[1]
odir <- argv[2]
workflows <- str_split_1(argv[3], ",") |> str_trim() |> str_to_lower()

source(file.path(get_script_dir(), "rsrc", "check_pairs.R"))

pairing <- read_tsv(pairing_file, show_col_types = FALSE, progress = FALSE)

missing_cols <- setdiff(c("NORMAL_ID", "TUMOR_ID"), names(pairing))
if (length(missing_cols) > 0) {
  cat(str_glue(
    "\nERROR: {pairing_file} is missing column(s): ",
    str_c(missing_cols, collapse = ", "), "\n\n"
  ))
  quit(status = 1)
}

missing <- find_missing_outputs(pairing, odir, workflows)
checked <- intersect(workflows, pair_output_files$workflow)
unchecked <- unchecked_workflows(workflows)
n_pairs <- nrow(distinct(pairing, TUMOR_ID, NORMAL_ID))

report <- c(
  str_glue("Pair output check: {format(Sys.time(), '%Y-%m-%d %H:%M:%S')}"),
  str_glue("Pairing: {pairing_file}"),
  str_glue("Output: {odir}"),
  str_glue("Pairs: {n_pairs}"),
  str_glue("Workflows checked: {str_c(checked, collapse = ', ')}"),
  if (length(unchecked) > 0) {
    str_glue("Not checked (no per-pair output file): {str_c(unchecked, collapse = ', ')}")
  },
  ""
)

if (nrow(missing) == 0) {

  report <- c(report, "OK: every pair has the output of every checked workflow")

} else {

  n_missing <- n_distinct(missing$TUMOR_ID, missing$NORMAL_ID)
  report <- c(
    report,
    str_glue("WARNING: {n_missing} of {n_pairs} pairs are missing output"),
    "",
    "PAIR\tWORKFLOW\tMISSING_FILE",
    str_glue("{missing$TUMOR_ID}__{missing$NORMAL_ID}\t{missing$workflow}\t{missing$file}")
  )

}

fs::dir_create(file.path(odir, "runlog"))
writeLines(report, file.path(odir, "runlog", "pair_check.txt"))

cat("\n", str_c(report, collapse = "\n"), "\n\n", sep = "")

quit(status = if (nrow(missing) == 0) 0 else 3)
