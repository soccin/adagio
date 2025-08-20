require(tidyverse)

#' Identify Failed Processes
#'
#' Filters trace data to identify processes that have failed (not COMPLETED or CACHED).
#' Returns the most recent attempt for each unique process name.
#'
#' @param trace_data Tibble containing trace data with status information
#' @return Tibble containing failed processes with the most recent attempt for each name
#' @export
#' @examples
#' failed_processes <- get_failed_processes(trace_data)
get_failed_processes <- function(trace_data) {
  trace_data %>%
    arrange(desc(complete)) %>%
    filter(!status %in% c("COMPLETED", "CACHED")) %>%
    distinct(name, .keep_all = TRUE)
}

#' Identify Failed Processes by Sample
#'
#' Similar to get_failed_processes but groups by sample instead of name.
#' Useful when the same process runs for multiple samples.
#'
#' @param trace_data Tibble containing trace data with status and sample information
#' @return Tibble containing failed processes with the most recent attempt for each sample
#' @export
#' @examples
#' failed_by_sample <- get_failed_processes_by_sample(trace_data)
get_failed_processes_by_sample <- function(trace_data) {
  trace_data %>%
    arrange(desc(complete)) %>%
    filter(!status %in% c("COMPLETED", "CACHED")) %>%
    distinct(sample, .keep_all = TRUE)
}

#' Get Processes Without Success
#'
#' Identifies process names that have no COMPLETED or CACHED instances.
#'
#' @param trace_data Tibble containing trace data
#' @return Tibble showing process names with no successful completions
#' @export
#' @examples
#' never_completed <- get_processes_without_success(trace_data)
get_processes_without_success <- function(trace_data) {
  status_summary <- trace_data %>%
    select(process, tag, name, status) %>%
    group_by(name) %>%
    count(status) %>%
    spread(status, n, fill = 0)
  
  status_summary %>%
    filter(is.na(COMPLETED) | COMPLETED == 0) %>%
    filter(is.na(CACHED) | CACHED == 0)
}

#' Create Failed Process Report
#'
#' Generates a comprehensive report of failed processes with key information
#' for debugging and analysis.
#'
#' @param trace_data Tibble containing trace data
#' @return Tibble with essential information about failed processes
#' @export
#' @examples
#' failure_report <- create_failure_report(trace_data)
create_failure_report <- function(trace_data) {
  get_failed_processes(trace_data) %>%
    select(sample, process, status, exit, native_id, hash) %>%
    arrange(sample)
}

#' Add SLURM Job Status to Failed Processes
#'
#' Enhances failed process data with SLURM job status information.
#' Requires slurm_utils.R to be sourced.
#'
#' @param failed_processes Tibble from get_failed_processes()
#' @return Tibble with additional SLURM state information
#' @export
#' @examples
#' # Source slurm utilities first
#' source("slurm_utils.R")
#' enhanced_report <- add_slurm_status(failed_processes)
add_slurm_status <- function(failed_processes) {
  # Check if SLURM functions are available
  if (!exists("get_slurm_state")) {
    if (file.exists("slurm_utils.R")) {
      source("slurm_utils.R")
    } else {
      warning("slurm_utils.R not found. SLURM status not added.")
      return(failed_processes)
    }
  }
  
  failed_processes %>%
    mutate(slurm_state = get_slurm_state(native_id)) %>%
    select(sample, hash, native_id, process, status, exit, slurm_state, duration, time)
}

#' Get Process Details for Specific Sample and Process
#'
#' Retrieves detailed information for a specific sample and process combination.
#'
#' @param trace_data Tibble containing trace data
#' @param sample_name Character string of sample name to filter
#' @param process_pattern Character string pattern to match process names
#' @return Tibble with filtered process details
#' @export
#' @examples
#' details <- get_sample_process_details(trace_data, "C-FY4MHU_C-FY4MHU-T1-wgs__C-FY4MHU_C-FY4MHU-N1-wgs", "RunNeo")
get_sample_process_details <- function(trace_data, sample_name, process_pattern) {
  trace_data %>%
    filter(sample == sample_name & grepl(process_pattern, process)) %>%
    select(hash:exit)
}

#' Generate Comprehensive Status Report
#'
#' Creates a complete status report combining failure analysis and SLURM information.
#'
#' @param trace_files Vector of trace file paths or single trace file list path
#' @return List containing various analysis results
#' @export
#' @examples
#' # From trace file list
#' report <- generate_status_report("../RunFilesPass1/traceFilesAll_250819.txt")
#' # From vector of files
#' trace_files <- c("file1.txt", "file2.txt")
#' report <- generate_status_report(trace_files)
generate_status_report <- function(trace_files) {
  # Load required functions
  if (file.exists("nextflow_analysis.R")) {
    source("nextflow_analysis.R")
  }
  
  # Handle input: either file list path or vector of files
  if (length(trace_files) == 1 && file.exists(trace_files)) {
    trace_files <- load_trace_file_list(trace_files)
  }
  
  # Process all trace data
  trace_data <- process_multiple_traces(trace_files)
  
  # Generate various reports
  list(
    trace_data = trace_data,
    failed_processes = get_failed_processes(trace_data),
    failed_by_sample = get_failed_processes_by_sample(trace_data),
    processes_without_success = get_processes_without_success(trace_data),
    failure_report = create_failure_report(trace_data),
    status_summary = get_status_summary(trace_data)
  )
}