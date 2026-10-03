# Display defaults for every Excel file the scripts write
# ========================================================
# Sourced by xlsx_report.R (openxlsx2) and xlsx_legacy.R (openxlsx).

# Sheet zoom in percent. Excel's default 100 is too small for the group.
XLSX_ZOOM <- 150

# Workbook window position and size in twips (1/20 point). Without an
# explicit size Excel for Mac opens the file full screen. About 1600 x 1000
# points at (200, 150).
XLSX_WINDOW <- list(x = 4000, y = 3000, width = 32000, height = 20000)
