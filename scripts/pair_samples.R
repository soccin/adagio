#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) {
  stop("Usage: pair_samples.R <MAPFILE>")
}
mapfile <- args[1]
outfile <- sub("_sample_mapping\\.txt$", "_sample_pairing.txt", mapfile)

map <- read.delim(mapfile, header = FALSE, sep = "\t",
                  stringsAsFactors = FALSE, check.names = FALSE)
samps <- unique(map[[2]])

m <- regmatches(samps, regexec("^(.*)_(.*)$", samps))
patient <- vapply(m, `[`, "", 2)
stype <- vapply(m, `[`, "", 3)

normals <- samps[stype == "N"]
tumors <- samps[stype != "N"]
names(normals) <- patient[stype == "N"]
names(tumors) <- patient[stype != "N"]

pairs <- data.frame(
  NORMAL = normals[names(tumors)],
  TUMOR = tumors,
  stringsAsFactors = FALSE
)

write.table(pairs, outfile, sep = "\t", quote = FALSE,
            row.names = FALSE, col.names = FALSE)
cat("Wrote", nrow(pairs), "pairs to", outfile, "\n")
