# Nextflow Trace Report
#
# Parses execution trace files from a Nextflow run, identifies failed
# processes, queries SLURM for job states, and writes an Excel summary
# plus a Markdown-formatted status report to stdout.

# Load required libraries
suppressPackageStartupMessages(require(tidyverse))

# Progress logging helper. The Markdown report is written to stdout (piped to
# `tee`), so all progress messages must go to stderr to avoid corrupting it.
log_progress <- function(...) {
  ts <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  message(str_c("[", ts, "] ", ...))
}

log_progress("Starting Nextflow trace report")

# Source the function modules
SDIR <- get_script_dir()
RDIR <- file.path(SDIR, "rsrc/nf-reports")
source(file.path(RDIR, "trace_parser.R"))
source(file.path(RDIR, "nextflow_analysis.R"))
source(file.path(RDIR, "status_reports.R"))
source(file.path(RDIR, "slurm_utils.R"))

# Load trace file list and process all traces
log_progress("Searching for trace files under out/")
trace_files <- fs::dir_ls("out", recur = 2, regex = "/execution_trace_.*txt$")
log_progress("Found ", length(trace_files), " trace file(s); parsing")
all_trace_data <- process_multiple_traces(trace_files)
log_progress("Parsed ", nrow(all_trace_data), " trace record(s)")

# Remove duplicate hashes (CACHED runs keep the latest status)
trace_data <- all_trace_data |>
  mutate(RID = row_number()) |>
  arrange(hash, status) |>
  distinct(hash, .keep_all = TRUE) |>
  arrange(RID)

# Get status summary — keep only processes with at least one failure
log_progress("Computing status summary")
qc0 <- get_status_summary(trace_data) |>
  filter(FAILED > 0) |>
  mutate(STATUS = ifelse(COMPLETED > 0, "WARN", "ERROR")) |>
  arrange(STATUS, name)

# Identify failed processes
log_progress(nrow(qc0), " process(es) with failures")
failed <- qc0 |> pull(name)
failed_rpt <- trace_data |>
  filter(name %in% failed) |>
  arrange(name, RID) |>
  select(sample, process, status, exit, native_id, hash, everything())

if (nrow(failed_rpt) != 0) {
  n_query <- failed_rpt |> filter(status == "FAILED") |> nrow()
  log_progress("Querying SLURM state for ", n_query, " failed job(s)")
  failed_states <- failed_rpt |>
    filter(status == "FAILED") |>
    rowwise() |>
    mutate(slurm_state = seff_field(native_id, "State")) |>
    select(name, exit, slurm_state, hash, native_id, sample)
}

log_progress("Writing nfTraceReport_v1.xlsx")
write_xlsx(
  list(
    Summary = qc0,
    FAILED  = failed_rpt
  ),
  "nfTraceReport_v1.xlsx"
)

log_progress("Writing Markdown report to stdout")
writeLines("\n# Nextflow Trace Report")
writeLines("\n## Job Status\n")
knitr::kable(qc0) |> writeLines()
if (nrow(failed_rpt) != 0) {
  writeLines("\n## Failed Reasons\n")
  knitr::kable(failed_states) |> writeLines()
} else {
  writeLines("\n\nNo Failed Jobs.")
}
writeLines("\n\n")

log_progress("Done")
