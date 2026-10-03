# Nextflow Analysis Tools

This directory contains R functions for analyzing Nextflow trace files and generating status reports for pipeline runs.

## Production use: `scripts/nfTraceReport.R`

`scripts/nfTraceReport.R` is the only production caller. The run scripts
(`bin/runTempoWGSBam.sh`, `bin/runTempoWESCohort.sh`, `bin/makeTempoBams.sh`)
run it after Nextflow exits. It:

- reads `out/*/pipeline_info/execution_trace_*.txt`
- writes `nfTraceReport_v1.xlsx` (sheets `Summary` and `FAILED`)
- prints a Markdown summary to stdout, which the run scripts save as
  `RUN_REPORT_<date>_.md`
- looks up the SLURM state of failed tasks with `seff_field()`

## File Organization

### Core Modules

- **`trace_parser.R`** - Core functions for reading and parsing Nextflow trace files
  - `read_nf_trace()` - Read and clean trace files
  - `parse_nextflow_time()` - Parse time strings to durations
  - `extract_samples_from_tags()` - Extract sample names from tags
  - `clean_trace_columns()` - Clean trace column names (snake_case)
  - `validate_trace_data()` - Validate trace data integrity

- **`nextflow_analysis.R`** - Functions for processing multiple trace files
  - `load_trace_file_list()` - Load trace file paths from list
  - `process_multiple_traces()` - Process multiple trace files
  - `get_process_timing()` - Analyze timing information
  - `get_status_summary()` - Summarize process statuses

- **`status_reports.R`** - Functions for failure analysis and reporting
  - `get_failed_processes()` - Identify failed processes
  - `get_failed_processes_by_sample()` - Failed processes per sample
  - `get_processes_without_success()` - Processes with no successful attempt
  - `create_failure_report()` - Generate failure summary
  - `add_slurm_status()` - Enhance with SLURM job information
  - `get_sample_process_details()` - Trace rows for one sample and process pattern
  - `generate_status_report()` - Comprehensive analysis

- **`slurm_utils.R`** - SLURM integration utilities
  - `seff_field()` - One field of `seff` output for a job (used by `nfTraceReport.R`)
  - `get_slurm_state()` - Get job states from SLURM (vectorized `get_slurm_state_1()`)
  - `get_slurm_state_chunk()` - Efficient batch queries

### Usage Examples

- **`example_usage.R`** - Demonstrates how to use the functions

## Quick Start

```r
# Load required libraries
require(tidyverse)

# Source the modules
source("trace_parser.R")
source("nextflow_analysis.R")
source("status_reports.R")

# Generate comprehensive report
report <- generate_status_report("path/to/trace_file_list.txt")

# Access different components
failed_processes <- report$failed_processes
status_summary <- report$status_summary
```

## Function Documentation

Functions have Roxygen2 comments with parameter and return descriptions.
Most also have examples and `@export`; `seff_field()` and the internal
`get_slurm_state_1()` do not.

## Dependencies

- `tidyverse` - Data manipulation and visualization
- `lubridate` - Date/time handling (loaded automatically)
- `glue`, `stringr` - used by `slurm_utils.R`
- SLURM `seff` and `sacct` on the PATH for the SLURM functions
- `nfTraceReport.R` also needs `fs`, `knitr`, `openxlsx` and
  `scripts/rsrc/xlsx_legacy.R`
