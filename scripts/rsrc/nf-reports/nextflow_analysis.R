require(tidyverse)

#' Load Multiple Nextflow Trace Files
#'
#' Reads a list of trace file paths and loads all trace files into a single dataframe.
#' 
#' @param trace_file_list_path Path to text file containing list of trace file paths
#' @return Character vector of trace file paths
#' @export
#' @examples
#' trace_files <- load_trace_file_list("../RunFilesPass1/traceFilesAll_250819.txt")
load_trace_file_list <- function(trace_file_list_path) {
  scan(trace_file_list_path, "", quiet = TRUE)
}

#' Process Multiple Nextflow Trace Files
#'
#' Loads and processes multiple Nextflow trace files, combining them into a single
#' dataframe with sample information extracted from tags.
#'
#' @param trace_files Vector of trace file paths
#' @return Tibble containing combined trace data with sample information
#' @export
#' @examples
#' trace_files <- load_trace_file_list("trace_list.txt")
#' combined_data <- process_multiple_traces(trace_files)
process_multiple_traces <- function(trace_files) {
  map_dfr(trace_files, read_nf_trace) %>%
    extract_samples_from_tags()
}

#' Get Process Duration Summary
#'
#' Analyzes duration and timing information for processes in trace data.
#'
#' @param trace_data Tibble containing trace data from process_multiple_traces()
#' @return Tibble with timing information including duration and realtime
#' @export
#' @examples
#' timing_info <- get_process_timing(trace_data)
get_process_timing <- function(trace_data) {
  trace_data %>%
    select(time, submit:realtime, duration1, realtime1) %>%
    mutate(duration_period = seconds_to_period(duration1)) %>%
    arrange(desc(duration1))
}

#' Get Process Status Summary
#'
#' Provides a summary of process statuses by name.
#'
#' @param trace_data Tibble containing trace data
#' @return Tibble with status counts by process name
#' @export
#' @examples
#' status_summary <- get_status_summary(trace_data)
get_status_summary <- function(trace_data) {
  trace_data %>%
    select(process, tag, name, status) %>%
    group_by(name) %>%
    count(status) %>%
    spread(status, n, fill = 0)
}