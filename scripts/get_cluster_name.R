#' Get Cluster Name
#'
#' Determines which compute cluster the script is running on by checking
#' environment variables and matching against known cluster names.
#'
#' @return Character string of cluster name ("IRIS" or "JUNO"), or NA if unknown
get_cluster_name <- function() {
  
  # Extract zone from environment variable
  get_zone_from_env <- function() {
    zone_env <- Sys.getenv("CDC_JOINED_ZONE")
    if (zone_env == "") return(NA)
    
    zone_parts <- strsplit(zone_env, ",")[[1]]
    if (length(zone_parts) == 0) return(NA)
    
    gsub("^CN=", "", zone_parts[1])
  }
  
  # Find matching cluster prefix
  partial_prefix_match <- function(target, choices) {
    if (is.na(target) || length(target) == 0) return(NA)
    if (length(choices) == 0) return(NA)
    
    for (choice in choices) {
      if (!is.na(choice) && startsWith(target, choice)) {
        return(choice)
      }
    }
    
    return(NA)
  }
  
  known_clusters <- c("IRIS", "JUNO")
  cluster <- get_zone_from_env()
  
  # Fallback check for JUNO using LSF environment
  if (is.na(cluster)) {
    lsf_path <- Sys.getenv("LSF_ENVDIR")
    if (lsf_path == "/admin/lsfjuno/lsf/conf") {
      cluster <- "JUNO"
    }
  }
  
  partial_prefix_match(cluster, known_clusters)
}