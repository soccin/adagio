# Example Usage of Nextflow Analysis Functions
#
# This script demonstrates how to use the refactored functions to analyze
# Nextflow runs and generate status reports.


# Load required libraries
suppressPackageStartupMessages(require(tidyverse))

# Source the function modules
SDIR=get_script_dir()
RDIR=file.path(SDIR,"rsrc/nf-reports")
source(file.path(RDIR,"trace_parser.R"))
source(file.path(RDIR,"nextflow_analysis.R"))
source(file.path(RDIR,"status_reports.R"))
source(file.path(RDIR,"slurm_utils.R"))

# Example 1: Basic workflow from history.R
# Load trace file list and process all traces
trace_files <- fs::dir_ls("out",recur=2,regex="/execution_trace_.*txt$")
all_trace_data <- process_multiple_traces(trace_files)

# Get rid of duplicate hash's (CACHED runs)
#
trace_data=all_trace_data %>%
  mutate(RID=row_number()) %>%
  arrange(hash,status) %>%
  distinct(hash,.keep_all=T) %>%
  arrange(RID)

# Get status summary
qc0=get_status_summary(trace_data) %>% filter(FAILED>0) %>% mutate(STATUS=ifelse(COMPLETED>0,"WARN","ERROR")) %>% arrange(STATUS,name)

# Identify failed processes
failed=qc0 %>% pull(name)
failed_rpt=trace_data %>% filter(name %in% failed) %>% arrange(name,RID) %>% select(sample,process,status,exit,native_id,hash,everything())

failed_states=failed_rpt %>% filter(status=="FAILED") %>% rowwise %>% mutate(slurm_state=seff_field(native_id,"State")) %>% select(name,exit,slurm_state,hash,native_id,sample)

write_xlsx(
  list(
    Summary=qc0,
    FAILED=failed_rpt
  ),
  "nfTraceReport_v1.xlsx"
)

writeLines("\n# Nextflow Trace Report")
writeLines("\n## Failed/Warn job list\n")
knitr::kable(qc0) |> writeLines()
writeLines("\n## Failed Reasons\n")
knitr::kable(failed_states) |> writeLines()
writeLines("\n\n")