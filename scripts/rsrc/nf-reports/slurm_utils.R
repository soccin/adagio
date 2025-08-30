#' Get SLURM Job State (Single Job)
#'
#' Internal function to get the SLURM state for a single job ID.
#' Handles invalid job IDs gracefully.
#'
#' @param job_id Character or numeric job ID
#' @return Character string of job state or NA if invalid/not found
#' @keywords internal
get_slurm_state_1 <- function(job_id) {
  # Handle invalid job IDs
  if (is.na(job_id) || job_id == "" || job_id == "-" || !grepl("^[0-9]+(_[0-9]+)*$", job_id)) {
    return(NA_character_)
  }

  cmd <- paste("sacct -j", job_id, "-P -n --format=State")
  result <- system(cmd, intern = TRUE)

  if (length(result) == 0) {
    return(NA_character_)
  }

  return(result[1])
}

#' Get SLURM Job State (Vectorized)
#'
#' Gets SLURM job states for one or more job IDs using sacct command.
#' Automatically handles invalid job IDs and returns NA for missing jobs.
#'
#' @param job_id Character or numeric vector of job IDs
#' @return Character vector of job states (e.g., "COMPLETED", "FAILED", "RUNNING")
#' @export
#' @examples
#' get_slurm_state("12345")
#' get_slurm_state(c("12345", "12346", "12347"))
get_slurm_state <- Vectorize(get_slurm_state_1, USE.NAMES = FALSE)

#' Get SLURM Job State in Chunks (Optimized)
#'
#' Efficiently queries SLURM job states for large numbers of jobs by processing
#' them in chunks to avoid command line length limits. More efficient than
#' the vectorized version for large job lists.
#'
#' @param job_id Character or numeric vector of job IDs
#' @param chunk_size Integer specifying how many jobs to query per sacct call (default: 100)
#' @return Character vector of job states corresponding to input job IDs
#' @export
#' @examples
#' # For large job lists, this is more efficient than get_slurm_state
#' job_states <- get_slurm_state_chunk(large_job_list, chunk_size = 50)
get_slurm_state_chunk <- function(job_id, chunk_size = 100) {
  # Handle NAs and invalid job IDs upfront
  valid_jobs <- !is.na(job_id) &
                job_id != "" &
                job_id != "-" &
                grepl("^[0-9]+(_[0-9]+)*$", job_id)

  # Initialize result vector
  result_states <- rep(NA_character_, length(job_id))

  # If no valid jobs, return all NAs
  if (!any(valid_jobs)) {
    return(result_states)
  }

  valid_job_ids <- job_id[valid_jobs]
  valid_indices <- which(valid_jobs)

  # Process in chunks to avoid command line length limits
  for (i in seq(1, length(valid_job_ids), by = chunk_size)) {
    end_idx <- min(i + chunk_size - 1, length(valid_job_ids))
    chunk_jobs <- valid_job_ids[i:end_idx]
    chunk_indices <- valid_indices[i:end_idx]

    # Query this chunk
    job_list <- paste(chunk_jobs, collapse = ",")
    cmd <- paste("sacct -j", job_list, "-P -n --format=JobID,State")
    sacct_result <- system(cmd, intern = TRUE)

    if (length(sacct_result) > 0) {
      # Parse results into a lookup table
      parsed <- do.call(rbind, strsplit(sacct_result, "\\|"))
      lookup <- data.frame(
        job = parsed[, 1],
        state = parsed[, 2],
        stringsAsFactors = FALSE
      )

      # Match back to chunk job IDs
      for (j in seq_along(chunk_jobs)) {
        original_idx <- chunk_indices[j]
        matches <- lookup$state[lookup$job == job_id[original_idx]]
        if (length(matches) > 0) {
          result_states[original_idx] <- matches[1]
        }
      }
    }
  }

  return(result_states)
}
