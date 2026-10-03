# FACETS sample and focal-segment rules
# =====================================
# The only definition of the two rules every report applies to FACETS
# results. Sourced by report01.R, qcReport01.R, reportFacets01.R and
# reportAll.R. Do not restate the thresholds in a report script; call the
# functions below. The thresholds are locked, so assigning to them in a
# report script is an error.
#
# A change here changes the content of all four reports. When changing a
# threshold:
#   - run test_facets_rules.R
#   - bump the output versions in reportFacets01.R, reportAll.R and
#     report01.R, and the file names quoted in docs/output.md,
#     docs/output.html, docs/METHODS_CNV_GENES.md and
#     docs/DESCRIPTION_FOCAL_GENES.md
#   - update the numbers quoted in docs/DESCRIPTION_ALL_REPORT.md,
#     docs/DESCRIPTION_FOCAL_GENES.md and docs/METHODS_CNV_GENES.md
#   - these outputs have no version in their names and are overwritten on
#     a rerun: facetsFailedSamples (qcReport01.R) and
#     post/plots/facets/*_facets_{purity,hisens}.seg (reportFacets01.R)

# Remove bindings locked by an earlier source() of this file
rm(list = intersect(c("max_abs_diplogr", "max_focal_seg_length"), ls()))

max_abs_diplogr <- 0.5       # sample gate on |dipLogR| when facets_qc is FALSE
max_focal_seg_length <- 1e6  # a segment this long (bp) or shorter is focal

lockBinding("max_abs_diplogr", environment())
lockBinding("max_focal_seg_length", environment())

#' Does a sample pass the FACETS sample rule?
#'
#' A sample passes if facets_qc is TRUE or |dipLogR| is below
#' max_abs_diplogr. A missing value never passes a sample: a missing
#' dipLogR does not rescue a QC failure, and a missing facets_qc counts as
#' a QC failure.
#'
#' @param facets_qc Logical vector, the facets_qc column of *.facets_qc.txt
#' @param dipLogR Numeric vector, the dipLogR column of the same file
#' @return Logical vector, never NA
facets_sample_pass <- function(facets_qc, dipLogR) {
  dplyr::coalesce(facets_qc, FALSE) |
    dplyr::coalesce(abs(dipLogR) < max_abs_diplogr, FALSE)
}

#' Is a copy number segment focal?
#'
#' @param seg_length Segment length in bp (seg_end - seg_start), the
#'   seg_length column of cna_genelevel.txt
#' @return Logical vector, never NA; a missing length is not focal
is_focal_seg <- function(seg_length) {
  dplyr::coalesce(seg_length <= max_focal_seg_length, FALSE)
}
