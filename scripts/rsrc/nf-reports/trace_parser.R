require(tidyverse)
require(lubridate)

#' Read Nextflow Trace File
#'
#' Reads and processes a Nextflow trace file, converting time fields and
#' cleaning percentage columns. This function handles the raw trace output
#' from Nextflow and converts it into a clean tibble format.
#'
#' @param trace_file Path to the Nextflow trace file (TSV format)
#' @return Tibble containing processed trace data with duration and timing fields
#' @export
#' @examples
#' trace_data <- read_nf_trace("path/to/trace.txt")
read_nf_trace <- function(trace_file) {
  if (!file.exists(trace_file)) {
    stop(paste("Trace file not found:", trace_file))
  }
  
  read_tsv(trace_file, show_col_types = FALSE, progress = FALSE) %>%
    # Clean percentage columns by removing % symbols
    mutate(across(matches("%"), ~ gsub("%", "", .))) %>%
    mutate(across(matches("%"), as.numeric)) %>%
    # Remove % from column names
    rename_with(~ gsub("%", "", .), everything()) %>%
    # Calculate duration fields
    mutate(
      duration1 = as.numeric(complete - submit),
      realtime1 = as.numeric(complete - start),
      time = parse_nextflow_time(time)
    ) %>%
    suppressWarnings()
}

#' Parse Nextflow Time String to Duration
#'
#' Converts Nextflow time strings (e.g., "1h 30m 45s") to lubridate duration objects.
#' Handles various time unit formats including days, hours, minutes, seconds, and milliseconds.
#'
#' @param time_str Character vector of time strings with units (d, h, m, s, ms)
#' @return Duration object representing the parsed time in seconds
#' @export
#' @examples
#' parse_nextflow_time("1h 30m 45s")
#' parse_nextflow_time(c("2h", "30m", "45s"))
#' parse_nextflow_time("1d 12h 30m")
parse_nextflow_time <- function(time_str) {
  # Handle vectorized input
  if (length(time_str) == 0) {
    return(duration())
  }
  
  # Handle individual cases for vectorized input
  result <- vector("list", length(time_str))
  
  for (i in seq_along(time_str)) {
    if (is.na(time_str[i]) || time_str[i] == "" || time_str[i] == "-") {
      result[[i]] <- duration(0)
      next
    }
    
    # Convert Nextflow time format to lubridate-compatible format
    duration_str <- time_str[i] %>%
      # Handle days
      gsub("(\\d+)d", "\\1 days ", .) %>%
      # Handle hours
      gsub("(\\d+)h", "\\1 hours ", .) %>%
      # Handle milliseconds (must come before minutes and seconds)
      gsub("(\\d+)ms", "0.001 seconds", .) %>%
      # Handle minutes (not followed by 's' to avoid matching 'ms')
      gsub("(\\d+)m(?!s)", "\\1 minutes ", ., perl = TRUE) %>%
      # Handle seconds (not preceded by 'm' to avoid matching 'ms')
      gsub("(?<!m)(\\d+)s", "\\1 seconds ", ., perl = TRUE)
    
    # Parse with lubridate duration
    result[[i]] <- tryCatch({
      duration(duration_str)
    }, error = function(e) {
      warning(paste("Failed to parse time string:", time_str[i]))
      duration(0)
    })
  }
  
  # Convert list to duration vector
  do.call(c, result)
}

#' Extract Sample Names from Nextflow Tags
#'
#' Extracts sample identifiers from Nextflow tag fields by removing everything
#' after the "@" symbol. This is useful for grouping processes by sample when
#' the tag contains sample information followed by additional metadata.
#'
#' @param trace_data Tibble containing Nextflow trace data with a 'tag' column
#' @return Tibble with added 'sample' column as the first column
#' @export
#' @examples
#' trace_with_samples <- extract_samples_from_tags(trace_data)
extract_samples_from_tags <- function(trace_data) {
  if (!"tag" %in% names(trace_data)) {
    warning("No 'tag' column found in trace data. Returning original data.")
    return(trace_data)
  }
  
  trace_data %>%
    mutate(sample = gsub("@.*", "", tag)) %>%
    select(sample, everything())
}

#' Clean Trace Data Column Names
#'
#' Standardizes column names in trace data by removing special characters
#' and converting to snake_case format.
#'
#' @param trace_data Tibble containing trace data
#' @return Tibble with cleaned column names
#' @export
#' @examples
#' clean_trace <- clean_trace_columns(trace_data)
clean_trace_columns <- function(trace_data) {
  trace_data %>%
    rename_with(~ gsub("[%()]", "", .)) %>%
    rename_with(~ gsub("\\s+", "_", .)) %>%
    rename_with(~ tolower(.))
}

#' Validate Trace Data
#'
#' Checks if trace data contains expected columns and valid data types.
#'
#' @param trace_data Tibble containing trace data
#' @return Logical indicating whether trace data is valid
#' @export
#' @examples
#' if (validate_trace_data(trace_data)) { # proceed with analysis }
validate_trace_data <- function(trace_data) {
  required_cols <- c("task_id", "status", "process")
  
  if (!all(required_cols %in% names(trace_data))) {
    missing_cols <- setdiff(required_cols, names(trace_data))
    warning(paste("Missing required columns:", paste(missing_cols, collapse = ", ")))
    return(FALSE)
  }
  
  if (nrow(trace_data) == 0) {
    warning("Trace data is empty")
    return(FALSE)
  }
  
  TRUE
}

# Legacy function name for backward compatibility
#' @rdname extract_samples_from_tags
#' @export
get_samples_from_tags <- extract_samples_from_tags