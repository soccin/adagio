# TERT Mutation Report Generator
#
# Purpose:
#   Extract and report all TERT (Telomerase Reverse Transcriptase) gene
#   mutations from somatic variant MAF files. TERT mutations, particularly
#   promoter mutations, are important in cancer as they can lead to telomerase
#   reactivation and cellular immortalization.
#
# Input:
#   - Unfiltered somatic MAF files in the out/ directory tree
#     (files matching pattern: *.somatic.unfiltered.maf)
#
# Output:
#   - Excel file: Proj_<projNo>_TERT_Muts_v1.xlsx
#     Contains filtered TERT mutations with selected annotation columns
#

# Define columns to include in the TERT mutation report
# Includes variant annotation, allele information, coverage, and filter status
reportCols00 <- c(
  "Sample",
  "Hugo_Symbol", "Chromosome", "Start_Position", "Variant_Classification",
  "Variant_Type", "Reference_Allele", "Tumor_Seq_Allele2", "HGVSp",
  "HGVSp_Short", "t_var_freq", "t_depth", "t_alt_count", "n_depth",
  "n_alt_count", "FILTER", "ExAC_FILTER", "Strelka2FILTER", "gnomAD_FILTER"
)

require(tidyverse)

# Read all somatic MAF files, combine them, and filter for TERT mutations
maf0 <- fs::dir_ls("out", recur = TRUE, regex = ".somatic.unfiltered.maf$") |>
  map(read_tsv) |>
  bind_rows(.id="Sample") |>
  mutate(Sample=basename(Sample)%>%gsub(".somatic.*","",.)) %>%
  select(all_of(reportCols00)) |>
  filter(grepl("^TERT$", Hugo_Symbol))

# Generate output filename based on project number
projNo <- basename(fs::dir_ls("out"))
rFile=cc("Proj",projNo,"TERT_Muts","v1.xlsx")

# Write TERT mutations to Excel file
write_xlsx(maf0,rFile)

