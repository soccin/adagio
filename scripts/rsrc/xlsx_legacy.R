# Excel display defaults for openxlsx (legacy) workbooks
# =======================================================
# The older scripts build workbooks with openxlsx (createWorkbook,
# write.xlsx). These helpers apply the display defaults of xlsx_defaults.R
# to such a workbook: a zoom of XLSX_ZOOM on every sheet and an explicit
# window size.
#
#   wb <- openxlsx::createWorkbook(); ...; finalize_xlsx(wb)
#   openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
#
# or, for the one-call case that used openxlsx::write.xlsx / write_xlsx:
#
#   write_xlsx_report(list(Sheet = tbl), path)

#' Directory of the file being sourced, found by walking the call frames for
#' the ofile variable source() sets. Falls back to the working directory.
rsrc_dir <- function() {
  for (i in rev(seq_len(sys.nframe()))) {
    f <- sys.frame(i)$ofile
    if (!is.null(f)) return(dirname(f))
  }
  "."
}
source(file.path(rsrc_dir(), "xlsx_defaults.R"))

#' Apply the display defaults to an openxlsx workbook
#'
#' openxlsx exposes the sheet views and book views only as XML strings, so
#' the zoom and window attributes are edited in place. The workbook object
#' is a reference class, so it is modified in place and also returned.
#'
#' @param wb openxlsx Workbook
#' @param zoom Sheet zoom in percent
#' @return wb
finalize_xlsx <- function(wb, zoom = XLSX_ZOOM) {
  for (i in seq_along(wb$worksheets)) {
    wb$worksheets[[i]]$sheetViews <- gsub(
      '(?<=zoomScale=")[0-9]+', zoom,
      wb$worksheets[[i]]$sheetViews, perl = TRUE
    )
  }
  wb$workbook$bookViews <- sprintf(
    '<bookViews><workbookView xWindow="%d" yWindow="%d" windowWidth="%d" windowHeight="%d"/></bookViews>',
    XLSX_WINDOW$x, XLSX_WINDOW$y, XLSX_WINDOW$width, XLSX_WINDOW$height
  )
  invisible(wb)
}

#' Write tables to an xlsx file with the display defaults
#'
#' Drop-in replacement for openxlsx::write.xlsx (and the write_xlsx wrapper
#' in ~/.Rprofile).
#'
#' @param x A data frame or a named list of data frames, one sheet each
#' @param file Output path
#' @param ... Passed to openxlsx::buildWorkbook
#' @return Invisibly, file
write_xlsx_report <- function(x, file, ...) {
  wb <- openxlsx::buildWorkbook(x, ...)
  finalize_xlsx(wb)
  openxlsx::saveWorkbook(wb, file, overwrite = TRUE)
  invisible(file)
}
