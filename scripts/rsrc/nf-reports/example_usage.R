# Example Usage of Nextflow Analysis Functions
#
# This script demonstrates how to use the refactored functions to analyze
# Nextflow runs and generate status reports.

# Load required libraries
require(tidyverse)

# Source the function modules
source("trace_parser.R")
source("nextflow_analysis.R")
source("status_reports.R")

# Example 1: Basic workflow from history.R
# Load trace file list and process all traces
trace_files <- load_trace_file_list("../RunFilesPass1/traceFilesAll_250819.txt")
all_trace_data <- process_multiple_traces(trace_files)

# Get status summary
status_summary <- get_status_summary(all_trace_data)
print("Status Summary by Process:")
print(status_summary)

# Example 2: Identify failed processes
failed_processes <- get_failed_processes(all_trace_data)
print(paste("Found", nrow(failed_processes), "failed processes"))

# Create basic failure report
failure_report <- create_failure_report(all_trace_data)
print("Failed Processes Summary:")
print(failure_report)

# Example 3: Enhanced report with SLURM status
# Note: This requires SLURM access and may take time for large job lists
enhanced_report <- add_slurm_status(failed_processes)
print("Enhanced Report with SLURM Status:")
print(enhanced_report)

# Example 4: Comprehensive status report (all-in-one)
# This generates all reports at once
full_report <- generate_status_report("../RunFilesPass1/traceFilesAll_250819.txt")

# Access different components of the report
print(paste("Total processes:", nrow(full_report$trace_data)))
print(paste("Failed processes:", nrow(full_report$failed_processes)))
print(paste("Processes that never succeeded:", nrow(full_report$processes_without_success)))

# Example 5: Analyze specific sample and process
sample_details <- get_sample_process_details(
  all_trace_data, 
  "C-FY4MHU_C-FY4MHU-T1-wgs__C-FY4MHU_C-FY4MHU-N1-wgs", 
  "RunNeo"
)
print("Sample-specific process details:")
print(sample_details)