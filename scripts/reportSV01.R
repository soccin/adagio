# Setup and dependencies
VERSION <- "v5"
PROOT <- get_script_dir()
source(file.path(PROOT, "rsrc/read_tempo_sv.R"))
argv <- commandArgs(trailing = TRUE)

suppressPackageStartupMessages(require(tidyverse))

# Read all SV BEDPE files and combine
# Using .final.bedpe instead of clustered output which fails on unmatched samples
sv_files <- fs::dir_ls("out", recur = TRUE, regex = "\\.final\\.bedpe$")
sv_data <- map(sv_files, read_tempo_sv_somatic, .progress = TRUE) |>
  bind_rows()

# Get full list of tumors from pairing file
# Handles cases where samples have no SVs
pairing_files <- fs::dir_ls("out", recur = TRUE, regex = "pairing_bam_tempo.tsv")
tumors <- pairing_files |>
  read_tsv(show_col_types = FALSE, progress = FALSE) |>
  pull(TUMOR_ID)

if (nrow(sv_data) == 0) {
  cat("\nNo structure variants found\n\n")
} else {

  type_convert <- function(x) {
    quietly(readr::type_convert)(x) |> pluck("result")
  }

  # Remove unnecessary columns
  sv_data <- sv_data |>
    select(-INFO_A, -INFO_B, -FORMAT, -TUMOR, -NORMAL)

  # Reorder columns: core info, then AD/PE/SR/PR/PS, then annotations
  sv_data <- sv_data |>
    select(
      1:CC_Chr_Band,
      matches("_(AD|PE|SR|PR|PS)$"),
      matches("^CC|^DGv"),
      matches("CONSENSUS"),
      everything()
    ) |>
    type_convert()

  # Calculate VAF for each caller
  sv_data <- sv_data |>
    mutate(
      # Delly VAFs
      t_delly_SpanVAF = t_delly_DV / (t_delly_DV + t_delly_DR),
      t_delly_JuncVAF = t_delly_RV / (t_delly_RV + t_delly_RR),
      n_delly_SpanVAF = n_delly_DV / (n_delly_DV + n_delly_DR),
      n_delly_JuncVAF = n_delly_RV / (n_delly_RV + n_delly_RR),
      # Svaba VAFs
      t_svaba_VAF = t_svaba_AD / t_svaba_DP,
      n_svaba_VAF = n_svaba_AD / n_svaba_DP
    ) |>
    # Manta split reads need parsing
    separate(t_manta_SR, c("t_manta_SRR", "t_manta_SRV"), remove = FALSE) |>
    mutate(
      t_manta_JuncVAF = as.numeric(t_manta_SRV) /
        (as.numeric(t_manta_SRV) + as.numeric(t_manta_SRR))
    )

  # Select final columns for output
  sv_events <- sv_data |>
    select(
      1:CC_Chr_Band,
      matches("VAF"),
      matches("_(AD|PE|SR|PR|PS|DR|DV|RR|RV)$"),
      matches("^CC|^DGv"),
      matches("CONSENSUS"),
      NORMAL_ID,
      UUID
    )

  # Load column descriptions
  col_desc <- read_csv(file.path(PROOT, "rsrc/svColTypeDescriptions.csv"),show_col_types=F,progress=F)

  # Create sample summary (count SVs per sample)
  event_counts <- tibble(TUMOR_ID = basename(sv_files) |> gsub("__.*", "", x = _)) |>
    left_join(count(sv_events, TUMOR_ID),by=join_by(TUMOR_ID)) |>
    mutate(n = ifelse(is.na(n), 0, n)) |>
    rename(NumSVs = n)
  sample_data <- left_join(tibble(TUMOR_ID=tumors),sv_counts,by=join_by(TUMOR_ID))

}

# Determine project number and output file name
proj_no <- fs::dir_ls("out") |>
  grep("/metrics", x = _, invert = TRUE, value = TRUE) |>
  basename()

if (!grepl("^Proj_", proj_no)) {
  proj_no <- cc("Proj", proj_no)
}

report_file <- cc(proj_no, "SV_Report01", paste0(VERSION, ".xlsx"))
report_dir <- "post/reports"
fs::dir_create(report_dir)

if (nrow(sv_data) > 0) {

  # Write Excel report
  write_xlsx(
    list(
      SampleData = sample_data,
      SVEvents = sv_events,
      ColDescriptions = col_desc
    ),
    file.path(report_dir, report_file)
  )

} else {
  write(
    "\nThere are no SV's\n",
    file.path(report_dir, "README_NoSVs.txt")
  )
}
