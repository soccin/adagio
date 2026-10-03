# Tests for facets_rules.R
# ========================
# Run after any change to facets_rules.R:
#
#   Rscript scripts/rsrc/test_facets_rules.R
#
# Exits with an error on the first failed check. The cases are written
# against the thresholds, not their current values, so they do not need
# editing when a threshold changes.

source(file.path(get_script_dir(), "facets_rules.R"))

eps <- 1e-9

# Sample rule
# ===========

sample_cases <- tibble::tribble(
  ~facets_qc, ~dipLogR,                ~expected,
  TRUE,       0,                       TRUE,
  TRUE,       max_abs_diplogr + 1,     TRUE,   # QC pass ignores dipLogR
  TRUE,       NA,                      TRUE,
  FALSE,      0,                       TRUE,
  FALSE,      max_abs_diplogr - eps,   TRUE,
  FALSE,      -max_abs_diplogr + eps,  TRUE,
  FALSE,      max_abs_diplogr,         FALSE,  # the bound itself fails
  FALSE,      -max_abs_diplogr,        FALSE,
  FALSE,      max_abs_diplogr + eps,   FALSE,
  FALSE,      NA,                      FALSE,  # missing dipLogR does not rescue
  NA,         0,                       TRUE,   # missing QC, rescued by dipLogR
  NA,         max_abs_diplogr,         FALSE,
  NA,         NA,                      FALSE
)

stopifnot(identical(
  facets_sample_pass(sample_cases$facets_qc, sample_cases$dipLogR),
  sample_cases$expected
))

# Focal rule
# ==========

focal_cases <- tibble::tribble(
  ~seg_length,               ~expected,
  1,                         TRUE,
  max_focal_seg_length - 1,  TRUE,
  max_focal_seg_length,      TRUE,   # the bound itself is focal
  max_focal_seg_length + 1,  FALSE,
  NA,                        FALSE
)

stopifnot(identical(is_focal_seg(focal_cases$seg_length), focal_cases$expected))

# Thresholds are locked
# =====================

assign_error <- tryCatch(
  {
    max_abs_diplogr <- 0
    NULL
  },
  error = function(e) conditionMessage(e)
)
stopifnot(!is.null(assign_error), max_abs_diplogr != 0)

# A second source() must still work
source(file.path(get_script_dir(), "facets_rules.R"))

message("facets_rules.R: all checks passed")
