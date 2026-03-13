# Nextflow Trace Report
#
# Parses execution trace files from a Nextflow run, identifies failed
# processes, queries SLURM for job states, and writes an Excel summary
# plus a Markdown-formatted status report to stdout.

# Load required libraries
suppressPackageStartupMessages(require(tidyverse))

# Source the function modules
SDIR <- get_script_dir()
RDIR <- file.path(SDIR, "rsrc/nf-reports")
source(file.path(RDIR, "trace_parser.R"))
source(file.path(RDIR, "nextflow_analysis.R"))
source(file.path(RDIR, "status_reports.R"))
source(file.path(RDIR, "slurm_utils.R"))

# Load trace file list and process all traces
trace_files <- fs::dir_ls("out", recur = 2, regex = "/execution_trace_.*txt$")
all_trace_data <- process_multiple_traces(trace_files)

# Remove duplicate hashes (CACHED runs keep the latest status)
trace_data <- all_trace_data |>
  mutate(RID = row_number()) |>
  arrange(hash, status) |>
  distinct(hash, .keep_all = TRUE) |>
  arrange(RID)

# Get status summary — keep only processes with at least one failure
qc0 <- get_status_summary(trace_data) |>
  filter(FAILED > 0) |>
  mutate(STATUS = ifelse(COMPLETED > 0, "WARN", "ERROR")) |>
  arrange(STATUS, name)

# Identify failed processes
failed <- qc0 |> pull(name)
failed_rpt <- trace_data |>
  filter(name %in% failed) |>
  arrange(name, RID) |>
  select(sample, process, status, exit, native_id, hash, everything())

if (nrow(failed_rpt) != 0) {
  failed_states <- failed_rpt |>
    filter(status == "FAILED") |>
    rowwise() |>
    mutate(slurm_state = seff_field(native_id, "State")) |>
    select(name, exit, slurm_state, hash, native_id, sample)
}

write_xlsx(
  list(
    Summary = qc0,
    FAILED  = failed_rpt
  ),
  "nfTraceReport_v1.xlsx"
)

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
