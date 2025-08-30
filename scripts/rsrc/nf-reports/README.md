# Nextflow Analysis Tools

This directory contains R functions for analyzing Nextflow trace files and generating status reports for pipeline runs.

## File Organization

### Core Modules

- **`trace_parser.R`** - Core functions for reading and parsing Nextflow trace files
  - `read_nf_trace()` - Read and clean trace files
  - `parse_nextflow_time()` - Parse time strings to durations
  - `extract_samples_from_tags()` - Extract sample names from tags
  - `validate_trace_data()` - Validate trace data integrity

- **`nextflow_analysis.R`** - Functions for processing multiple trace files
  - `load_trace_file_list()` - Load trace file paths from list
  - `process_multiple_traces()` - Process multiple trace files
  - `get_process_timing()` - Analyze timing information
  - `get_status_summary()` - Summarize process statuses

- **`status_reports.R`** - Functions for failure analysis and reporting
  - `get_failed_processes()` - Identify failed processes
  - `create_failure_report()` - Generate failure summary
  - `add_slurm_status()` - Enhance with SLURM job information
  - `generate_status_report()` - Comprehensive analysis

- **`slurm_utils.R`** - SLURM integration utilities
  - `get_slurm_state()` - Get job states from SLURM
  - `get_slurm_state_chunk()` - Efficient batch queries

### Usage Examples

- **`example_usage.R`** - Demonstrates how to use the functions
- **`history.R`** - Original command history (for reference)

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

All functions include Roxygen2 documentation with:
- Parameter descriptions
- Return value specifications  
- Usage examples
- Export declarations for package development

## Dependencies

- `tidyverse` - Data manipulation and visualization
- `lubridate` - Date/time handling (loaded automatically)

## Migration from Original Code

The original interactive analysis from `history.R` has been refactored into reusable functions. Key changes:

- `analyzeTrace.R` → `trace_parser.R` (better name, enhanced functions)
- Added comprehensive error handling and validation
- Improved function names and documentation
- Modular organization for easier maintenance
- Backward compatibility maintained where possible