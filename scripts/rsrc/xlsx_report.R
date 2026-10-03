# Excel report writer (openxlsx2)
# ===============================
# Shared by reportSV01.R and reportAll.R. openxlsx2 is called with :: so
# nothing is attached or masked.
#
# Every workbook gets the display defaults in xlsx_defaults.R: a zoom of
# XLSX_ZOOM on every sheet and an explicit window size (without one Excel
# for Mac opens the file full screen).

suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
  library(stringr)
})

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

#' Excel number format for one column
#'
#' VAF columns are fractions shown as percentages with one decimal; Pct
#' columns as whole percentages. Whole-number columns get a thousands
#' separator (genomic coordinates included); other numerics get two
#' decimals. Non-numeric columns get no format.
#'
#' @param col_name Column name
#' @param values Column values
#' @return Excel format code, or NA if the column needs none
excel_num_fmt <- function(col_name, values) {
  if (!is.numeric(values)) {
    return(NA_character_)
  }
  if (str_detect(col_name, "VAF")) {
    return("0.0%")
  }
  if (str_detect(col_name, "^Pct$|^Freq$")) {
    return("0%")
  }
  if (all(values == round(values), na.rm = TRUE)) {
    return("#,##0")
  }
  "0.00"
}

#' Column widths that fit their content, capped
#'
#' The cap matters: a single long annotation would otherwise stretch one
#' column past the width of the screen.
#'
#' @param tbl Table being written
#' @param max_width Widest column allowed, in characters
#' @return Numeric width per column
fit_col_widths <- function(tbl, max_width = 60) {
  header_width <- nchar(names(tbl)) * 1.2  # fudge for the bold header font
  # na.rm matters: nchar(NA_character_) is NA, not 2
  value_width <- map_dbl(tbl, \(x) max(nchar(as.character(x)), 0, na.rm = TRUE))
  pmin(pmax(header_width, value_width) + 2, max_width)
}

#' Add one table to the workbook as a reader-friendly sheet
#'
#' Bold wrapped header, frozen header row, fitted column widths, per-column
#' number formats, zoom set to XLSX_ZOOM.
#'
#' Excel cannot represent NaN/Inf, so they are written as error codes
#' (#VALUE!/#NUM!); those become empty cells here instead. `na.strings =
#' NULL` leaves NA cells genuinely absent rather than openxlsx2's default
#' #N/A or an empty text cell, so ISBLANK works and numeric columns stay
#' numeric.
#'
#' @param wb openxlsx2 workbook
#' @param sheet_name Name for the new worksheet
#' @param tbl Table to write
#' @return The workbook with the sheet added
add_report_sheet <- function(wb, sheet_name, tbl) {
  tbl <- tbl |>
    mutate(across(where(is.numeric), \(x) replace(x, !is.finite(x), NA)))

  header <- openxlsx2::wb_dims(rows = 1, cols = seq_along(tbl))

  wb <- wb |>
    openxlsx2::wb_add_worksheet(sheet_name) |>
    openxlsx2::wb_add_data(x = tbl, na.strings = NULL) |>
    openxlsx2::wb_add_font(dims = header, bold = "1") |>
    openxlsx2::wb_add_cell_style(
      dims = header,
      wrap_text = TRUE,
      horizontal = "left"
    ) |>
    openxlsx2::wb_freeze_pane(first_active_row = 2) |>
    openxlsx2::wb_set_col_widths(
      cols = seq_along(tbl),
      widths = fit_col_widths(tbl)
    ) |>
    openxlsx2::wb_set_sheetview(zoom_scale = XLSX_ZOOM)

  # One call per distinct format, covering all its columns at once: openxlsx2
  # registers a new format entry on every call and Excel only tolerates ~200
  # per workbook, which per-column calls would exceed on a wide sheet
  if (nrow(tbl) > 0) {
    data_rows <- 1 + seq_len(nrow(tbl))
    col_fmts <- map2_chr(names(tbl), tbl, excel_num_fmt)

    for (fmt in unique(na.omit(col_fmts))) {
      dims <- which(col_fmts == fmt) |>
        map_chr(\(j) openxlsx2::wb_dims(rows = data_rows, cols = j)) |>
        str_c(collapse = ",")
      wb <- openxlsx2::wb_add_numfmt(wb, dims = dims, numfmt = fmt)
    }
  }

  wb
}

#' Write the report sheets to a formatted xlsx file
#'
#' @param sheets Named list of tables, one worksheet each
#' @param path Output .xlsx path
#' @return Invisibly, path
write_report_workbook <- function(sheets, path) {
  wb <- openxlsx2::wb_workbook()
  for (sheet_name in names(sheets)) {
    wb <- add_report_sheet(wb, sheet_name, sheets[[sheet_name]])
  }
  wb <- openxlsx2::wb_set_bookview(
    wb,
    x_window = XLSX_WINDOW$x, y_window = XLSX_WINDOW$y,
    window_width = XLSX_WINDOW$width, window_height = XLSX_WINDOW$height
  )
  openxlsx2::wb_save(wb, path, overwrite = TRUE)
  invisible(path)
}
