#!/usr/bin/env Rscript

# Reformat TEMPO SV Depth Report for Excel Distribution
# Reads tempoSVDepth.csv and column descriptions, then creates
# a multi-sheet Excel file with data and documentation

library(tidyverse)
library(openxlsx)

# Read SV depth data
sv_depth <- read_csv("tempoSVDepth.csv")

# Read column descriptions
col_desc <- read_csv("tempoSVDepth_COLUMNS.csv")

# Prepare simplified column descriptions for Excel sheet
col_desc_clean <- col_desc |>
  select(
    Column_Name,
    Description,
    Recommended_Threshold,
    Summary = For_Biologists,
    Details = For_Analysts
  ) |>
  mutate(across(everything(), ~str_replace_all(., "N/A", "")))

# Write multi-sheet Excel file
write.xlsx(
  list(
    SVDepth = sv_depth,
    ColumnDesc = col_desc_clean
  ),
  "Proj_17929_SV_DepthInfo_v1.xlsx"
)

cat("Excel file created: Proj_17929_SV_DepthInfo_v1.xlsx\n")
cat("  Sheet 1 (SVDepth): ", nrow(sv_depth), " variants x ", ncol(sv_depth), " columns\n", sep = "")
cat("  Sheet 2 (ColumnDesc): Column documentation\n")
