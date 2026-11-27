#
# makeTargetGC.R
#
# One-time asset for the QC background database: the GC content of each
# exome target. The intervals are exactly those of Alfred's per-target
# coverage (TC) section, so the target IDs join to the ones buildQCDb.R
# and read_alfred() build (Chr:Start-End; Start 0-based, End exclusive,
# as in the 5 bp padded BED that Tempo gives Alfred). Targets listed
# twice in TC are kept once.
#
# GC = (G + C) / (A + C + G + T) on the reference FASTA; N and any other
# letter are ignored. A target with no A, C, G or T gets NA.
#
# Reads the FASTA through its .fai index; submit with runMakeTargetGC.sh.
#

usage <- function() {
    cat("
Usage: Rscript makeTargetGC.R --alfred=FILE --fasta=FILE --out=FILE

  --alfred=FILE  one sample's Alfred QC file (<SAMPLE>.alfred.tsv.gz); its
                 TC section gives the intervals
  --fasta=FILE   reference FASTA with a .fai index
  --out=FILE     output .tsv.gz: TARGET, CHROM, START, END, LENGTH, GC
                 (an existing file is never overwritten)
")
}

args <- commandArgs(trailingOnly = TRUE)
if (any(args %in% c("-h", "--help"))) {
    usage()
    quit(status = 0)
}
opt <- as.list(setNames(sub("^--[A-Za-z-]+=", "", args), sub("^--([A-Za-z-]+)=.*", "\\1", args)))
need <- c("alfred", "fasta", "out")
if (!all(need %in% names(opt))) {
    usage()
    stop("Missing option(s): ", paste(setdiff(need, names(opt)), collapse = ", "), call. = FALSE)
}

suppressPackageStartupMessages({
    library(tidyverse)
    library(glue)
})

SDIR <- get_script_dir()
source(file.path(SDIR, "rsrc", "qcdb_readers.R"))

if (fs::file_exists(opt$out)) stop(glue("{opt$out} exists"), call. = FALSE)

tc <- read_alfred_sections(opt$alfred, "TC")$TC
if (is.null(tc)) stop(glue("No TC section in {opt$alfred}"), call. = FALSE)
message(glue("TC rows: {nrow(tc)}"))

# Target IDs from the file's own strings, as read_alfred() builds them
targets <- tc |>
    transmute(TARGET = str_c(Chr, ":", Start, "-", End), CHROM = Chr, START = as.integer(Start),
              END = as.integer(End)) |>
    distinct(TARGET, .keep_all = TRUE) |>
    mutate(LENGTH = END - START)
message(glue("Unique targets: {nrow(targets)}"))

fa <- Rsamtools::FaFile(opt$fasta)
faChroms <- read_tsv_quiet(str_c(opt$fasta, ".fai"), col_names = FALSE, col_types = cols(.default = "c"))$X1
badChroms <- setdiff(unique(targets$CHROM), faChroms)
if (len(badChroms) > 0) {
    stop(glue("Chromosomes not in {opt$fasta}: {str_c(badChroms, collapse = ', ')}"), call. = FALSE)
}

ranges <- GenomicRanges::GRanges(targets$CHROM, IRanges::IRanges(targets$START + 1L, targets$END))
freq <- Rsamtools::scanFa(fa, ranges) |>
    Biostrings::letterFrequency(c("A", "C", "G", "T"))
acgt <- rowSums(freq)

targets <- targets |>
    mutate(GC = if_else(acgt > 0, round((freq[, "G"] + freq[, "C"]) / acgt, 6), NA_real_))

fs::dir_create(dirname(opt$out))
write_tsv(targets, opt$out, na = "NA")

gcRange <- quantile(targets$GC, c(0.05, 0.5, 0.95), na.rm = TRUE) |> round(3)
message(glue("GC 5%, median, 95%: {str_c(gcRange, collapse = ', ')}; NA: {sum(is.na(targets$GC))}"))
message(glue("Wrote {opt$out}"))
