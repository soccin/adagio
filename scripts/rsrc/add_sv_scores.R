add_sv_scores <- function(df) {
  # Helper to pull the alt count (second value) from "ref,alt" strings
  alt_from_pair <- function(x) {
    as.numeric(sub("^[^,]*,", "", as.character(x)))
  }
  
  # Helper to take row-wise max while treating all-NA rows as NA (not -Inf)
  row_max <- function(mat) {
    out <- suppressWarnings(apply(mat, 1, max, na.rm = TRUE))
    out[is.infinite(out)] <- NA_real_
    out
  }
  
  # Spanning (paired-end) alt support
  span <- cbind(
    manta_PR = alt_from_pair(df$t_manta_PR),
    delly_DV = suppressWarnings(as.numeric(df$t_delly_DV)),
    svaba_DR = suppressWarnings(as.numeric(df$t_svaba_DR))
  )
  
  # Split-junction alt support
  split <- cbind(
    manta_SR = alt_from_pair(df$t_manta_SR),
    delly_RV = suppressWarnings(as.numeric(df$t_delly_RV)),
    svaba_SR = suppressWarnings(as.numeric(df$t_svaba_SR))
  )
  
  df$SCORE_SPAN  <- row_max(span)
  df$SCORE_SPLIT <- row_max(split)
  df$SCORE       <- pmax(df$SCORE_SPAN, df$SCORE_SPLIT, na.rm = TRUE)
  
  df
}
