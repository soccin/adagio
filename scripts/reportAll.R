# reportAll.R -- combined SV, SNV and CNV report
# ===============================================
# One workbook that puts the three somatic alteration types side by side.
# Run from the project directory (the one containing out/):
#
#   Rscript reportAll.R
#
# Sheets:
#   SampleSummary  one row per tumor in the pairing file: event counts by
#                  type, FACETS purity, ploidy, FGA, WGD and QC
#   GeneRanking    one row per gene ranked by the number of tumors with an
#                  SV, SNV or CNV event in it, each tumor counted once, with
#                  the count split by type (APTL cohort report, Table 1)
#   SVFreq_HV      recurrent SV gene pairs (the SVFreq sheet of the SV
#                  report) with the breakpoint distance and chromosome bands
#   ColDescriptions
#
# Event definitions (parameters below):
#   SV   a call in the .final.bedpe files; same-chromosome calls with the two
#        breakpoints closer than min_intra_chr_mb are dropped everywhere
#   SNV  a non-synonymous mutation in the cohort MAF, as in report01.R,
#        including the TERT promoter rescue from the unfiltered MAFs
#   CNV  a FACETS gene-level call with filter PASS or RESCUE on a segment of
#        fewer than max_focal_genes genes, on an autosome, from a sample with
#        facets_qc TRUE or |dipLogR| below max_abs_diplogr
#
# Output: post/reports/Proj_<no>_All_Report01_<VERSION>.xlsx

VERSION <- "v1"
PROOT <- get_script_dir()
source(file.path(PROOT, "rsrc/read_tempo_sv.R"))
source(file.path(PROOT, "rsrc/add_sv_scores.R"))
source(file.path(PROOT, "rsrc/read_pairing.R"))
source(file.path(PROOT, "rsrc/xlsx_report.R"))

suppressPackageStartupMessages(require(tidyverse))

# Parameters
# ==========

min_intra_chr_mb <- 1      # drop same-chromosome SVs shorter than this
max_focal_genes <- 10      # a CNV segment with fewer genes than this is focal
max_abs_diplogr <- 1.5     # FACETS sample gate when facets_qc is FALSE
min_tumors <- 2            # GeneRanking shows genes with at least this many tumors
min_sv_pct <- 0.05         # SVFreq_HV shows pairs in at least this fraction of tumors
genome <- "hg19"

lof_classes <- c(
  "Frame_Shift_Del", "Frame_Shift_Ins", "Nonsense_Mutation", "Splice_Site",
  "Translation_Start_Site", "Nonstop_Mutation"
)

#' Convert column types without the readr guessing messages
#'
#' @param tbl Table with character columns to convert
#' @return Table with converted column types
quiet_type_convert <- function(tbl) {
  quietly(readr::type_convert)(tbl) |>
    pluck("result")
}

#' Sorted, semicolon-separated list of the distinct samples
#'
#' @param x Character vector of sample ids
#' @return One string
collapse_samples <- function(x) {
  str_c(sort(unique(x)), collapse = "; ")
}

# Project and samples
# ===================

proj_no <- fs::dir_ls("out") |>
  str_subset("/metrics", negate = TRUE) |>
  basename()

if (!str_detect(proj_no, "^Proj_")) {
  proj_no <- cc("Proj", proj_no)
}

cohort_dir <- fs::dir_ls("out", recurse = 2, regexp = "cohort_level/default_cohort$")

pairing <- read_pairing()
tumors <- pairing$TUMOR_ID
n_tumors <- n_distinct(tumors)

# Cytogenetic bands
# =================
# UCSC cytoBand table; chromosome names are stored without the chr prefix to
# match the Tempo BEDPE and FACETS files

cytoband <- read_tsv(
  file.path(PROOT, "rsrc", str_glue("cytoBand_{genome}.txt.gz")),
  col_names = c("chrom", "band_start", "band_end", "band", "stain"),
  show_col_types = FALSE,
  progress = FALSE
) |>
  mutate(chrom = str_remove(chrom, "^chr")) |>
  select(-stain)

#' Chromosome band at each position, e.g. "1p31.1"
#'
#' Bands are half-open intervals, so a position on a boundary falls in one
#' band only. Positions off the table (or on an unlisted contig) give NA.
#'
#' @param chrom Chromosome names without chr prefix
#' @param pos Positions
#' @return Character vector of chromosome plus band
band_at <- function(chrom, pos) {
  tibble(chrom = as.character(chrom), pos = pos) |>
    left_join(
      cytoband,
      by = join_by(chrom, pos >= band_start, pos < band_end)
    ) |>
    mutate(label = if_else(is.na(band), NA_character_, str_c(chrom, band))) |>
    pull(label)
}

# Structural variants
# ===================

#' Orientation-independent gene-pair label for an SV
#'
#' Genes are sorted so that A/B and B/A give the same label. An unannotated
#' breakpoint is written as "." rather than dropped; SVs with neither end
#' annotated get NA so they are not all pooled into one pseudo-pair.
#'
#' @param gene1,gene2 Gene names at each breakpoint (NA or "" if unannotated)
#' @return Character vector of "GENEA::GENEB" labels, NA when both are missing
make_gene_pair <- function(gene1, gene2) {
  g1 <- na_if(gene1, "")
  g2 <- na_if(gene2, "")
  pair <- str_c(
    pmin(replace_na(g1, "."), replace_na(g2, ".")),
    pmax(replace_na(g1, "."), replace_na(g2, ".")),
    sep = "::"
  )
  if_else(is.na(g1) & is.na(g2), NA_character_, pair)
}

sv_files <- fs::dir_ls("out", recurse = TRUE, regexp = "\\.final\\.bedpe$")
sv_raw <- map(sv_files, read_tempo_sv_somatic, .progress = TRUE) |>
  bind_rows()

sv_empty <- tibble(
  TUMOR_ID = character(), TYPE = character(), gene1 = character(),
  gene2 = character(), CHROM_A = character(), START_A = numeric(),
  CHROM_B = character(), START_B = numeric(), NumCallersPass = numeric(),
  SCORE = numeric(), fusion = character(), in_frame = logical(),
  genePair = character(), same_chr = logical(), dist_mb = numeric(),
  bands = character()
)

sv_all <- if (nrow(sv_raw) == 0) {
  sv_empty
} else {
  sv_raw |>
    select(-INFO_A, -INFO_B, -FORMAT, -TUMOR, -NORMAL) |>
    quiet_type_convert() |>
    add_sv_scores() |>
    mutate(
      CHROM_A = as.character(CHROM_A),
      CHROM_B = as.character(CHROM_B),
      genePair = make_gene_pair(gene1, gene2),
      # iAnnotateSV writes "Protein Fusion: in frame {A:B}"; "mid-exon" and
      # "Transcript Fusion" are not in frame
      in_frame = str_detect(coalesce(fusion, ""), regex("in.?frame", ignore_case = TRUE)),
      same_chr = CHROM_A == CHROM_B,
      dist_mb = if_else(same_chr, abs(START_B - START_A) / 1e6, NA_real_),
      bands = str_c(band_at(CHROM_A, START_A), band_at(CHROM_B, START_B), sep = "-")
    ) |>
    select(all_of(names(sv_empty)))
}

# The distance filter applies to every sheet
sv_events <- sv_all |>
  filter(!same_chr | dist_mb >= min_intra_chr_mb)

message(
  "SV: ", nrow(sv_all), " calls, ", nrow(sv_events), " kept after dropping ",
  "same-chromosome calls under ", min_intra_chr_mb, " Mb"
)

# One row per tumor and gene with a breakpoint in the gene
sv_genes <- sv_events |>
  select(TUMOR_ID, gene1, gene2) |>
  pivot_longer(c(gene1, gene2), values_to = "Gene") |>
  mutate(Gene = na_if(Gene, "")) |>
  filter(!is.na(Gene)) |>
  distinct(TUMOR_ID, Gene)

# Point mutations
# ===============
# Same rows as the Mutations sheet of the SNV report: non-synonymous
# mutations of the cohort MAF plus TERT promoter (5'Flank) mutations rescued
# from the unfiltered per-pair MAFs, which Tempo's filters usually remove.

#' Read a Tempo MAF as character columns
#'
#' read_tsv is unreliable on these files (see report01.R), so use fread.
#'
#' @param path MAF path
#' @return Tibble of character columns
read_maf_chr <- function(path) {
  data.table::fread(
    path,
    skip = "Hugo_Symbol",
    sep = "\t",
    na.strings = c("", "NA"),
    colClasses = "character",
    showProgress = FALSE
  ) |>
    tibble()
}

#' Keep the mutations the reports count
#'
#' @param maf MAF tibble
#' @return Tibble with Sample, Gene, Class, Alteration, is_lof
non_synonymous <- function(maf) {
  maf |>
    select(
      Sample = Tumor_Sample_Barcode,
      Gene = Hugo_Symbol,
      Class = Variant_Classification,
      Alteration = HGVSp_Short
    ) |>
    filter(
      (!is.na(Alteration) & !str_detect(Alteration, "=$")) |
        (Gene == "TERT" & Class == "5'Flank")
    ) |>
    mutate(is_lof = Class %in% lof_classes)
}

maf_file <- fs::dir_ls(cohort_dir, regexp = "mut_somatic\\.maf$")
snv_cohort <- read_maf_chr(maf_file) |>
  non_synonymous()

tert_rescued <- fs::dir_ls("out", recurse = TRUE, regexp = "\\.somatic\\.unfiltered\\.maf$") |>
  map(\(f) read_maf_chr(f) |> filter(FILTER != "PASS")) |>
  bind_rows() |>
  non_synonymous() |>
  filter(Gene == "TERT", Class == "5'Flank")

snv_events <- bind_rows(snv_cohort, tert_rescued)

message(
  "SNV: ", nrow(snv_cohort), " non-synonymous mutations, ",
  nrow(tert_rescued), " TERT promoter mutations rescued"
)

# Copy number
# ===========

facets_qc <- fs::dir_ls("out", recurse = TRUE, regexp = "\\.facets_qc\\.txt$") |>
  map(\(f) read_tsv(f, col_types = cols(.default = "c"), show_col_types = FALSE, progress = FALSE)) |>
  bind_rows() |>
  quiet_type_convert() |>
  transmute(
    TUMOR_ID = str_remove(tumor_sample_id, "__.*"),
    facets_qc,
    Purity = purity_run_Purity,
    Ploidy = ploidy,
    FGA = fga,
    dipLogR,
    cnv_included = facets_qc | coalesce(abs(dipLogR) < max_abs_diplogr, FALSE)
  )

cnv_samples <- facets_qc |>
  filter(cnv_included) |>
  pull(TUMOR_ID)

message(
  "CNV: ", length(cnv_samples), " of ", nrow(facets_qc), " FACETS samples pass ",
  "(facets_qc or |dipLogR| < ", max_abs_diplogr, ")"
)

# One row per sample, gene and focal call. Dir follows the FACETS cn_state
# labels (the APTL "facets" preset); calls with no direction, e.g. INDETERMINATE,
# are not events.
cnv_events <- fs::dir_ls(cohort_dir, regexp = "cna_genelevel\\.txt$") |>
  read_tsv(show_col_types = FALSE, progress = FALSE) |>
  mutate(
    TUMOR_ID = str_remove(sample, "__.*"),
    chrom = as.character(chrom),
    Dir = case_when(
      str_detect(cn_state, "HOMDEL|HETLOSS|^LOSS|DOUBLE LOSS") ~ "loss",
      str_detect(cn_state, "^AMP|^GAIN|GAIN$") ~ "gain",
      str_detect(cn_state, "CNLOH") ~ "cnloh",
      TRUE ~ NA_character_
    ),
    focal = filter %in% c("PASS", "RESCUE") & coalesce(genes_on_seg < max_focal_genes, FALSE)
  ) |>
  filter(
    TUMOR_ID %in% cnv_samples,
    chrom %in% as.character(1:22),
    focal,
    !is.na(Dir)
  ) |>
  select(TUMOR_ID, Gene = gene, chrom, seg, seg_start, seg_end, tcn, lcn, cn_state, Dir)

# Sheet 1: sample summary
# =======================

count_by_tumor <- function(tbl, name) {
  tbl |>
    distinct() |>
    count(TUMOR_ID, name = name)
}

sample_data <- fs::dir_ls(cohort_dir, regexp = "sample_data\\.txt$") |>
  read_tsv(show_col_types = FALSE, progress = FALSE) |>
  transmute(
    TUMOR_ID = str_remove(sample, "__.*"),
    TotalMutations = Number_of_Mutations,
    WGD = WGD_status
  )

sample_summary <- pairing |>
  select(TUMOR_ID, NORMAL_ID) |>
  left_join(sv_events |> select(TUMOR_ID, SCORE) |> count(TUMOR_ID, name = "NumSV"), by = join_by(TUMOR_ID)) |>
  left_join(snv_events |> count(Sample, name = "NumSNV") |> rename(TUMOR_ID = Sample), by = join_by(TUMOR_ID)) |>
  left_join(snv_events |> filter(is_lof) |> count(Sample, name = "NumSNV_LoF") |> rename(TUMOR_ID = Sample), by = join_by(TUMOR_ID)) |>
  left_join(cnv_events |> select(TUMOR_ID, chrom, seg) |> count_by_tumor("NumCNV"), by = join_by(TUMOR_ID)) |>
  left_join(cnv_events |> select(TUMOR_ID, Gene) |> count_by_tumor("NumCNVGenes"), by = join_by(TUMOR_ID)) |>
  left_join(sample_data, by = join_by(TUMOR_ID)) |>
  left_join(facets_qc, by = join_by(TUMOR_ID)) |>
  mutate(
    across(c(NumSV, NumSNV, NumSNV_LoF), \(x) replace_na(x, 0L)),
    # A sample excluded from the CNV counts is blank, not zero
    across(c(NumCNV, NumCNVGenes), \(x) if_else(cnv_included, replace_na(x, 0L), NA_integer_))
  ) |>
  arrange(TUMOR_ID)

# Sheet 2: gene ranking
# =====================
# Each tumor counts once per gene in Tumors; the type columns count the
# tumors with that event type, so they can sum to more than Tumors.

gene_events <- bind_rows(
  sv_genes |> mutate(Type = "SV"),
  snv_events |> distinct(TUMOR_ID = Sample, Gene) |> mutate(Type = "SNV"),
  snv_events |> filter(is_lof) |> distinct(TUMOR_ID = Sample, Gene) |> mutate(Type = "SNV_LoF"),
  cnv_events |> distinct(TUMOR_ID, Gene) |> mutate(Type = "CNV"),
  cnv_events |> distinct(TUMOR_ID, Gene, Dir) |> transmute(TUMOR_ID, Gene, Type = str_c("CNV_", Dir))
)

type_cols <- c("SV", "SNV", "SNV_LoF", "CNV", "CNV_gain", "CNV_loss", "CNV_cnloh")

type_counts <- gene_events |>
  count(Gene, Type) |>
  mutate(Type = factor(Type, levels = type_cols)) |>
  pivot_wider(
    names_from = Type, values_from = n,
    values_fill = 0L, names_expand = TRUE
  )

gene_ranking <- gene_events |>
  filter(Type %in% c("SV", "SNV", "CNV")) |>
  distinct(TUMOR_ID, Gene) |>
  summarize(
    Tumors = n(),
    Samples = collapse_samples(TUMOR_ID),
    .by = Gene
  ) |>
  mutate(Pct = Tumors / n_tumors) |>
  left_join(type_counts, by = join_by(Gene)) |>
  arrange(desc(Tumors), desc(SV), desc(SNV), desc(CNV), Gene) |>
  mutate(Rank = min_rank(desc(Tumors))) |>
  filter(Tumors >= min_tumors) |>
  select(
    Rank, Gene, Tumors, Pct,
    SV, SNV, SNV_LoF, CNV, Gain = CNV_gain, Loss = CNV_loss, cnLOH = CNV_cnloh,
    Samples
  )

# Sheet 3: SV gene pairs
# ======================
# Pairs in at least min_sv_pct of the tumors; in a small cohort that reaches
# pairs seen in one tumor, and those are kept only when at least one call is
# an in-frame protein fusion. InFrame counts the pair's in-frame calls.
# Dist_Mb is the median breakpoint distance of the pair's calls and is blank
# for pairs joining two chromosomes. Bands lists each distinct band pair seen.

sv_freq <- sv_events |>
  filter(!is.na(genePair)) |>
  summarize(
    N = n_distinct(TUMOR_ID),
    InFrame = sum(in_frame),
    Dist_Mb = median(dist_mb),
    Bands = str_c(unique(na.omit(bands)), collapse = "; "),
    Samples = collapse_samples(TUMOR_ID),
    .by = genePair
  ) |>
  mutate(Pct = N / n_tumors) |>
  filter(Pct >= min_sv_pct, N > 1 | InFrame > 0) |>
  arrange(desc(N), desc(InFrame), genePair) |>
  select(genePair, N, InFrame, Dist_Mb, Bands, Pct, Samples)

# Column descriptions
# ===================

col_desc <- tribble(
  ~SHEET, ~FIELD, ~DESCRIPTION,
  "SampleSummary", "TUMOR_ID", "Tumor sample id from the pairing file",
  "SampleSummary", "NORMAL_ID", "Matched normal sample id",
  "SampleSummary", "NumSV", str_glue("Somatic SV calls, excluding same-chromosome calls with breakpoints closer than {min_intra_chr_mb} Mb"),
  "SampleSummary", "NumSNV", "Non-synonymous somatic mutations (the Mutations sheet of the SNV report, TERT promoter rescue included)",
  "SampleSummary", "NumSNV_LoF", str_glue("Of NumSNV, loss-of-function classes: {str_c(lof_classes, collapse = ', ')}"),
  "SampleSummary", "NumCNV", str_glue("Focal copy number segments: FACETS filter PASS or RESCUE, fewer than {max_focal_genes} genes, autosomes, with a gain, loss or cnLOH state. Blank when the sample fails the FACETS gate"),
  "SampleSummary", "NumCNVGenes", "Genes on the NumCNV segments",
  "SampleSummary", "TotalMutations", "All somatic mutations in the Tempo sample_data file, silent and non-coding included",
  "SampleSummary", "WGD", "Whole genome doubling status from FACETS",
  "SampleSummary", "facets_qc", "FACETS QC flag",
  "SampleSummary", "Purity", "FACETS purity (purity run)",
  "SampleSummary", "Ploidy", "FACETS ploidy",
  "SampleSummary", "FGA", "Fraction of the genome altered (FACETS)",
  "SampleSummary", "dipLogR", "FACETS diploid log ratio",
  "SampleSummary", "cnv_included", str_glue("TRUE when the sample contributes CNV events: facets_qc TRUE or |dipLogR| < {max_abs_diplogr}"),
  "GeneRanking", "Rank", "Rank by Tumors; ties share a rank",
  "GeneRanking", "Gene", "Gene symbol",
  "GeneRanking", "Tumors", "Tumors with an SV, SNV or CNV event in the gene, each tumor counted once",
  "GeneRanking", "Pct", str_glue("Tumors as a fraction of the {n_tumors} tumors in the pairing file"),
  "GeneRanking", "SV", "Tumors with an SV breakpoint annotated to the gene",
  "GeneRanking", "SNV", "Tumors with a non-synonymous mutation in the gene",
  "GeneRanking", "SNV_LoF", "Tumors with a loss-of-function mutation in the gene",
  "GeneRanking", "CNV", "Tumors with a focal CNV call in the gene (see NumCNV)",
  "GeneRanking", "Gain", "Tumors whose focal CNV call in the gene is a gain or amplification",
  "GeneRanking", "Loss", "Tumors whose focal CNV call in the gene is a loss or homozygous deletion",
  "GeneRanking", "cnLOH", "Tumors whose focal CNV call in the gene is copy-neutral LOH",
  "GeneRanking", "Samples", "Tumors counted in Tumors",
  "SVFreq_HV", "genePair", "Genes at the two breakpoints, sorted; a dot is an unannotated breakpoint",
  "SVFreq_HV", "N", str_glue("Tumors with a call joining the two genes; pairs in at least {100 * min_sv_pct}% of tumors are shown, and single-tumor pairs only when InFrame is above zero"),
  "SVFreq_HV", "InFrame", "Calls of the pair annotated as an in-frame protein fusion",
  "SVFreq_HV", "Dist_Mb", str_glue("Median distance between the breakpoints in Mb for same-chromosome pairs; blank for translocations. Pairs under {min_intra_chr_mb} Mb are removed"),
  "SVFreq_HV", "Bands", str_glue("Chromosome bands of the two breakpoints (UCSC {genome} cytoBand), one entry per distinct band pair among the calls"),
  "SVFreq_HV", "Pct", str_glue("N as a fraction of the {n_tumors} tumors in the pairing file"),
  "SVFreq_HV", "Samples", "Tumors counted in N"
) |>
  mutate(DESCRIPTION = as.character(DESCRIPTION))

# Write
# =====

report_dir <- "post/reports"
fs::dir_create(report_dir)
report_file <- file.path(report_dir, cc(proj_no, "All_Report01", str_c(VERSION, ".xlsx")))

write_report_workbook(
  list(
    SampleSummary = sample_summary,
    GeneRanking = gene_ranking,
    SVFreq_HV = sv_freq,
    ColDescriptions = col_desc
  ),
  report_file
)

message("Wrote ", report_file)
message("  SampleSummary: ", nrow(sample_summary), " samples")
message("  GeneRanking:   ", nrow(gene_ranking), " genes")
message("  SVFreq_HV:     ", nrow(sv_freq), " gene pairs")
