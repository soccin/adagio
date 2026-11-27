#
# Readers for the Tempo QC outputs used to build the QC background
# database (see ../buildQCDb.R and ../README.md), and the per-sample
# computations that buildQCDb.R (background) and qcdb_project_metrics.R
# (project) must do the same way.
#
# Every reader takes one file and returns a tibble. Per-sample readers
# return a SAMPLE column; per-pair readers return a PAIR column
# (TUMOR__NORMAL, as Tempo names the somatic folders).
#
# tumor_gene_mvlh() calls gene_mvlh() from scripts/rsrc/qc_pair_data.R;
# source that file to use it.
#

read_tsv_quiet <- function(file, ...) {
    read_tsv(file, show_col_types = FALSE, progress = FALSE, ...)
}

sample_from_path <- function(path, suffix) {
    basename(path) |> str_remove(suffix)
}

#
# Picard CollectHsMetrics: the metrics row and the coverage histogram
#
read_hs_metrics <- function(file) {
    lines <- read_lines(file, progress = FALSE)
    iMet <- str_which(lines, "^## METRICS CLASS")
    iHist <- str_which(lines, "^## HISTOGRAM")
    metrics <- read_tsv_quiet(I(lines[(iMet + 1):(iMet + 2)]), col_types = cols(.default = "c")) |>
        select(-any_of(c("SAMPLE", "LIBRARY", "READ_GROUP")), -BAIT_SET) |>
        mutate(across(everything(), as.numeric))
    hist <- read_tsv_quiet(I(lines[(iHist + 1):length(lines)]) |> str_subset("\\S"))
    list(
        metrics = metrics |> mutate(SAMPLE = sample_from_path(file, "\\.hs_metrics\\.txt$"), .before = 1),
        hist = hist |>
            rename(COVERAGE = 1, HQ_COVERAGE_COUNT = 2, UNFILTERED_BASEQ_COUNT = 3) |>
            mutate(SAMPLE = sample_from_path(file, "\\.hs_metrics\\.txt$"), .before = 1)
    )
}

#
# Picard CollectAlignmentSummaryMetrics (<SAMPLE>.asm.txt, written by
# scripts/picardqc/doPicardQC.sh): one row per CATEGORY (FIRST_OF_PAIR,
# SECOND_OF_PAIR, PAIR). metrics is the PAIR row; categories keeps all
# rows.
#
read_asm <- function(file) {
    sample <- sample_from_path(file, "\\.asm\\.txt$")
    lines <- read_lines(file, progress = FALSE)
    iMet <- str_which(lines, "^## METRICS CLASS")
    if (len(iMet) != 1) stop("no METRICS CLASS section")
    rows <- lines[-seq_len(iMet)]
    iEnd <- match(TRUE, !str_detect(rows, "\\S"), nomatch = len(rows) + 1)
    categories <- read_tsv_quiet(I(rows[seq_len(iEnd - 1)]), col_types = cols(.default = "c")) |>
        select(-any_of(c("SAMPLE", "LIBRARY", "READ_GROUP"))) |>
        mutate(across(-CATEGORY, as.numeric)) |>
        mutate(SAMPLE = sample, .before = 1)
    pair <- categories |> filter(CATEGORY == "PAIR")
    if (nrow(pair) != 1) stop("no PAIR row")
    list(metrics = pair |> select(-CATEGORY), categories = categories)
}

#
# Alfred: split the file into its sections (ME, IS, CO, ...). Each
# section starts with a header row whose first field is the section key.
#
read_alfred_sections <- function(file, keys) {
    lines <- read_lines(file, progress = FALSE) |> str_subset("^#", negate = TRUE)
    key <- str_extract(lines, "^[A-Z]{2}")
    keys |>
        set_names() |>
        map(function(k) {
            sec <- lines[key == k] |> str_remove(glue("^{k}\t"))
            if (len(sec) < 2) return(NULL)
            read_tsv_quiet(I(sec), col_types = cols(.default = "c"))
        })
}

read_alfred <- function(file, maxInsert = 1000, maxCov = 500) {
    sample <- sample_from_path(file, "\\.alfred\\.tsv\\.gz$")
    sec <- read_alfred_sections(file, c("ME", "IS", "CO", "GC", "BQ", "MQ", "CM", "IZ", "IC", "OT", "TC"))
    num <- function(df, cols) df |> mutate(across(all_of(cols), as.numeric))

    me <- sec$ME |>
        select(-Sample, -Library, -any_of(c("MedianReadLength", "DefaultLibraryLayout"))) |>
        mutate(across(everything(), as.numeric)) |>
        rename_with(\(x) str_replace(x, "^#", "N_")) |>
        mutate(SAMPLE = sample, .before = 1)

    insertSize <- sec$IS |>
        num(c("InsertSize", "Count")) |>
        filter(InsertSize <= maxInsert) |>
        group_by(InsertSize) |>
        summarize(Count = sum(Count), .groups = "drop") |>
        mutate(SAMPLE = sample, .before = 1)

    coverage <- sec$CO |>
        num(c("Coverage", "Count", "Quantile")) |>
        filter(Coverage <= maxCov) |>
        select(Coverage, Count, Quantile) |>
        mutate(SAMPLE = sample, .before = 1)

    gc <- sec$GC |>
        num(c("GCcontent", "fractionOfReads")) |>
        select(Source = Sample, GCcontent, fractionOfReads) |>
        mutate(Source = if_else(Source == "Reference", "Reference", "Sample")) |>
        mutate(SAMPLE = sample, .before = 1)

    baseQual <- sec$BQ |>
        num(c("Position", "BaseQual")) |>
        select(Read, Position, BaseQual) |>
        mutate(SAMPLE = sample, .before = 1)

    mapQual <- sec$MQ |>
        num(c("MappingQuality", "Count", "Fraction")) |>
        select(MappingQuality, Count, Fraction) |>
        mutate(SAMPLE = sample, .before = 1)

    chromMap <- sec$CM |>
        num(c("Size", "Mapped", "MappedFraction", "ObsExpRatio")) |>
        select(Chrom, Size, Mapped, MappedFraction, ObsExpRatio) |>
        mutate(SAMPLE = sample, .before = 1)

    indelSize <- sec$IZ |>
        num(c("Size", "Count")) |>
        select(InDel, Size, Count) |>
        mutate(SAMPLE = sample, .before = 1)

    indelContext <- sec$IC |>
        num(c("Count", "Fraction")) |>
        select(InDel, Homopolymer, Count, Fraction) |>
        mutate(SAMPLE = sample, .before = 1)

    onTarget <- sec$OT |>
        num(c("Extension", "OnTarget")) |>
        select(Extension, OnTarget) |>
        mutate(SAMPLE = sample, .before = 1)

    # Per-target coverage as two vectors (target IDs and coverage) so the
    # caller can build a target x sample matrix
    targetCov <- list(
        id = str_c(sec$TC$Chr, ":", sec$TC$Start, "-", sec$TC$End),
        cov = as.numeric(sec$TC$AvgCov)
    )

    list(
        metrics = me, insertSize = insertSize, coverage = coverage, gc = gc,
        baseQual = baseQual, mapQual = mapQual, chromMap = chromMap,
        indelSize = indelSize, indelContext = indelContext, onTarget = onTarget,
        targetCov = targetCov
    )
}

#
# Per-target GC table (TARGET, CHROM, START, END, LENGTH, GC), built once
# per target set by ../makeTargetGC.R on the intervals of Alfred's TC
# section
#
read_target_gc <- function(file) {
    read_tsv_quiet(file, col_types = cols(TARGET = "c", CHROM = "c", START = "i", END = "i", LENGTH = "i",
                                          GC = "d"))
}

#
# GC-bias curve of one sample (the exome version of QSee's COBALT GC
# plot). Each target's coverage is divided by the sample's median target
# coverage (over every TC row, as normMat in buildQCDb.R); then, over the
# autosomal targets, the median of that per GC bin. Targets listed twice
# in TC count once; targets with GC NA (all N) are left out. Bins with
# fewer than minTargets targets are dropped. GC_BIN is the bin midpoint.
#
# cov, targetIds: Alfred TC AvgCov and Chr:Start-End IDs (read_alfred()
# targetCov), in the same order. gcTable: read_target_gc().
#
target_gc_curve <- function(cov, targetIds, gcTable, binWidth = 0.01, minTargets = 100) {
    autosomes <- c(as.character(1:22), str_c("chr", 1:22))
    gc <- gcTable |>
        filter(CHROM %in% autosomes, !is.na(GC)) |>
        select(TARGET, GC)
    tibble(TARGET = targetIds, NORM_COV = cov / median(cov, na.rm = TRUE)) |>
        distinct(TARGET, .keep_all = TRUE) |>
        filter(!is.na(NORM_COV)) |>
        inner_join(gc, by = "TARGET") |>
        # the small offset keeps values on a bin edge (0.29 / 0.01 is
        # 28.999...) in the bin above, as exact arithmetic would
        mutate(GC_BIN = round((floor(GC / binWidth + 1e-9) + 0.5) * binWidth, 6)) |>
        summarize(
            N_TARGETS = n(),
            MEDIAN_NORM_COV = median(NORM_COV),
            Q25_NORM_COV = quantile(NORM_COV, 0.25, names = FALSE),
            Q75_NORM_COV = quantile(NORM_COV, 0.75, names = FALSE),
            .by = GC_BIN
        ) |>
        filter(N_TARGETS >= minTargets) |>
        arrange(GC_BIN)
}

#
# Alfred TC coverage as a table: TARGET, COV, LENGTH (End - Start), with
# targets listed twice kept once; and its length-weighted mean
#
alfred_target_table <- function(cov, targetIds) {
    tibble(TARGET = targetIds, COV = cov) |>
        distinct(TARGET, .keep_all = TRUE) |>
        mutate(LENGTH = as.numeric(str_extract(TARGET, "\\d+$")) - as.numeric(str_extract(TARGET, "(?<=:)\\d+")))
}

alfred_target_mean <- function(tc) {
    sum(tc$COV * tc$LENGTH) / sum(tc$LENGTH)
}

#
# Missed-variant likelihood of one tumor over the OncoKB genes, with the
# arguments of the per-pair QC pages (gene_mvlh() in
# scripts/rsrc/qc_pair_data.R, which must be sourced):
#   - geneCov: the tumor's Alfred TC coverage on the genes' targets,
#     targets listed twice kept once
#   - scale: Picard mean target coverage (hsmMeanCov) over the
#     length-weighted mean of the Alfred target coverage, so depths are
#     on Picard's scale (Alfred counts duplicates and low-quality reads)
#   - coding bases outside the targets left out (uncaptured = "drop")
# Returns gene_mvlh()'s table (GENE, MVLH, MEAN_DEPTH, CHROM,
# FRAC_IN_TARGETS), or NULL when purity is NA or the scale is not finite.
#
# cov, targetIds: as for target_gc_curve(). male: mvlh_male().
# genes: read_gene_resources() (scripts/rsrc/qc_pair_data.R).
#
tumor_gene_mvlh <- function(cov, targetIds, hsmMeanCov, purity, male, genes) {
    tc <- alfred_target_table(cov, targetIds)
    scale <- hsmMeanCov / alfred_target_mean(tc)
    if (len(scale) != 1 || !is.finite(scale)) return(NULL)
    geneCov <- tc |>
        filter(TARGET %in% genes$targets$TARGET) |>
        select(TARGET, COV)
    gene_mvlh(geneCov, genes$targets, genes$genes |> filter(ONCOKB), purity, male, scale, uncaptured = "drop")
}

#
# One X (and Y) allele for the MVLH: the normal's sex call
# (call_normal_sex() in scripts/rsrc/qc_sex.R) is Male, or it is not
# Female and the reported sex is Male. Vectorized; NA counts as not male.
#
mvlh_male <- function(call, reported) {
    coalesce(call == "Male" | (call != "Female" & coalesce(reported, "") == "Male"), FALSE)
}

#
# Qualimap bamqc: genome_results.txt from the raw data tarball. Lines of
# the form "key = value" are taken with their section name as prefix;
# "There is a X% of reference with a coverageData >= NX" lines become
# PCT_COV_GE_<N>X.
#
read_qualimap <- function(tarFile) {
    sample <- sample_from_path(tarFile, "_qualimap_rawdata\\.tar\\.gz$")
    exDir <- fs::file_temp(tmp_dir = Sys.getenv("TMPDIR", tempdir()))
    fs::dir_create(exDir)
    on.exit(fs::dir_delete(exDir))
    utils::untar(tarFile, exdir = exDir)
    gr <- fs::dir_ls(exDir, recurse = TRUE, regexp = "genome_results\\.txt$")
    lines <- read_lines(gr, progress = FALSE)

    section <- str_match(lines, "^>>>>>>> (.*)$")[, 2]
    section <- vctrs::vec_fill_missing(section, "down")

    kv <- tibble(section = section, line = str_squish(lines)) |>
        filter(str_detect(line, " = ")) |>
        separate_wider_regex(line, c(key = ".*?", " = ", value = ".*")) |>
        filter(!section %in% c("Input")) |>
        mutate(
            num = value |> str_remove("\\s*\\(.*$") |> str_remove_all(",|bp|X$|%") |> str_squish() |> as.numeric(),
            pct = str_match(value, "\\(([0-9.]+)%\\)")[, 2] |> as.numeric(),
            metric = str_c(section, "_", key) |> str_replace_all("[^A-Za-z0-9]+", "_") |> str_to_upper()
        )

    pctRows <- kv |>
        filter(!is.na(pct)) |>
        transmute(metric = str_c(metric, "_PCT"), num = pct)

    covRows <- tibble(line = str_squish(lines)) |>
        filter(str_detect(line, "^There is a")) |>
        transmute(
            metric = str_c("PCT_COV_GE_", str_match(line, ">= ([0-9]+)X")[, 2], "X"),
            num = as.numeric(str_match(line, "a ([0-9.]+)%")[, 2])
        )

    kvRows <- select(kv, metric, num)
    bind_rows(kvRows, pctRows, covRows) |>
        filter(!is.na(num)) |>
        distinct(metric, .keep_all = TRUE) |>
        pivot_wider(names_from = metric, values_from = num) |>
        mutate(SAMPLE = sample, .before = 1)
}

#
# fastp: one JSON per lane (file name SAMPLE@instrument@run@flowcell@lane_001)
#
read_fastp <- function(file) {
    d <- jsonlite::read_json(file)
    tag <- basename(file) |> str_remove("\\.fastp\\.json$")
    parts <- str_split_1(tag, "@")
    flat <- function(x, prefix) {
        x |>
            keep(\(v) is.numeric(v) && len(v) == 1) |>
            map(as.double) |>
            as_tibble() |>
            rename_with(\(n) str_c(prefix, n))
    }
    bind_cols(
        tibble(SAMPLE = parts[1], LANE_TAG = str_c(parts[-1], collapse = "@")),
        flat(d$summary$before_filtering, "before_"),
        flat(d$summary$after_filtering, "after_"),
        flat(d$filtering_result, "filter_"),
        tibble(
            duplication_rate = as.double(d$duplication$rate),
            insert_size_peak = as.double(d$insert_size$peak),
            insert_size_unknown = as.double(d$insert_size$unknown),
            adapter_trimmed_reads = as.double(d$adapter_cutting$adapter_trimmed_reads %||% NA_real_),
            adapter_trimmed_bases = as.double(d$adapter_cutting$adapter_trimmed_bases %||% NA_real_)
        )
    )
}

#
# Combine fastp lanes into one row per sample: counts are summed and
# rates are recomputed or weighted by reads
#
summarize_fastp <- function(lanes) {
    lanes |>
        group_by(SAMPLE) |>
        summarize(
            N_LANES = n(),
            # weighted means first: the sums below replace before_total_reads
            across(c(matches("_gc_content$"), duplication_rate, insert_size_peak, matches("_mean_length$")),
                   \(x) weighted.mean(x, before_total_reads)),
            across(c(matches("_(total_reads|total_bases|q20_bases|q30_bases)$"), starts_with("filter_"),
                     insert_size_unknown, adapter_trimmed_reads, adapter_trimmed_bases), sum),
            .groups = "drop"
        ) |>
        mutate(
            before_q20_rate = before_q20_bases / before_total_bases,
            before_q30_rate = before_q30_bases / before_total_bases,
            after_q20_rate = after_q20_bases / after_total_bases,
            after_q30_rate = after_q30_bases / after_total_bases,
            pct_reads_passed_filter = filter_passed_filter_reads / before_total_reads,
            pct_adapter_trimmed_reads = adapter_trimmed_reads / before_total_reads
        ) |>
        rename_with(\(x) str_c("FASTP_", str_to_upper(x)), -SAMPLE)
}

#
# fastp duplication histogram of one lane. In fastp 0.19.7 (Tempo's;
# src/duplicate.cpp) each read pair goes into one of 4^12 buckets by the
# first 12 bases of R1; a bucket keeps one representative (the pair with
# the smallest first 32 bases of R2) and counts how often that exact
# sequence was seen. Element j of duplication$histogram is the number of
# buckets whose representative was seen j times; the last, 31, is 31 or
# more. mean_gc is the mean GC of those reads. So N_SETS is a sample of
# distinct fragments, about one per bucket, per lane and before
# alignment. MEAN_GC is NA where N_SETS is 0 (fastp writes 0).
#
read_fastp_dup_hist <- function(file) {
    d <- jsonlite::read_json(file)
    parts <- basename(file) |>
        str_remove("\\.fastp\\.json$") |>
        str_split_1("@")
    nSets <- as.double(unlist(d$duplication$histogram))
    meanGc <- as.double(unlist(d$duplication$mean_gc))
    if (len(nSets) == 0 || len(nSets) != len(meanGc)) stop("no duplication histogram")
    tibble(
        SAMPLE = parts[1],
        LANE_TAG = str_c(parts[-1], collapse = "@"),
        DUP_LEVEL = seq_along(nSets),
        N_SETS = nSets,
        MEAN_GC = if_else(nSets > 0, meanGc, NA_real_)
    )
}

#
# Conpair
#
read_concordance <- function(file) {
    d <- read_tsv_quiet(file, col_types = cols(.default = "c"))
    tibble(
        PAIR = sample_from_path(file, "\\.concordance\\.txt$"),
        CONPAIR_CONCORDANCE = as.numeric(d[[2]][1])
    )
}

read_contamination <- function(file) {
    read_tsv_quiet(file) |>
        transmute(
            PAIR = sample_from_path(file, "\\.contamination\\.txt$"),
            SAMPLE = Sample_ID,
            CONPAIR_CONTAMINATION = Contamination / 100
        )
}

#
# FACETS: the facets-suite QC row (one per pair). Paths and run prefixes
# are dropped. Columns stay character here, because a column guessed
# from one file can differ in type from another (a value of NA in one
# file); convert_facets_qc() sets the types after the rows are bound.
#
read_facets_qc <- function(file) {
    read_tsv_quiet(file, col_types = cols(.default = "c")) |>
        select(-any_of(c("path", "purity_run_prefix", "hisens_run_prefix", "manual_note"))) |>
        rename(PAIR = tumor_sample_id)
}

convert_facets_qc <- function(df) {
    if (nrow(df) == 0) return(tibble(PAIR = character()))
    df |>
        type_convert(col_types = cols(.default = col_guess())) |>
        suppressMessages() |>
        mutate(across(where(is.logical), as.numeric))
}

#
# FACETS gene-level calls (facets/<pair>/<run>/<pair>.gene_level.txt):
# the number of genes with cn_state HOMDEL and filter PASS or RESCUE
# (QSee's "Deleted genes"). Calls facets-suite suppresses
# (suppress_large_homdel, suppress_segment_too_large) are left out: in
# the WES background they are 95% of HOMDEL gene rows, up to 6,536
# genes in one pair. The QC row's n_homdels counts segments.
#
FACETS_GENE_LEVEL_RE <- "/facets/[^/]+/[^/]+/[^/]+\\.gene_level\\.txt$"
FACETS_HOMDEL_FILTERS <- c("PASS", "RESCUE")

read_facets_gene_level <- function(file) {
    d <- read_tsv_quiet(file, col_types = cols(.default = "c"), col_select = c(gene, cn_state, filter))
    tibble(
        PAIR = sample_from_path(file, "\\.gene_level\\.txt$"),
        FACETS_N_HOMDEL_GENES = as.numeric(n_distinct(d$gene[d$cn_state %in% "HOMDEL" &
                                                                 d$filter %in% FACETS_HOMDEL_FILTERS]))
    )
}

read_sample_data <- function(file) {
    read_tsv_quiet(file, col_types = cols(.default = "c")) |>
        transmute(
            PAIR = sample,
            TEMPO_PURITY = as.numeric(purity),
            TEMPO_PLOIDY = as.numeric(str_trim(ploidy)),
            TEMPO_WGD = as.numeric(str_to_lower(WGD_status) == "true"),
            TEMPO_N_MUTATIONS = as.numeric(Number_of_Mutations),
            TEMPO_TMB = as.numeric(TMB)
        )
}

#
# Tempo QC status (from the multiqc folder). Row names are sample IDs.
#
read_tempo_status <- function(file) {
    read_tsv_quiet(file, col_types = cols(.default = "c"), name_repair = "unique_quiet") |>
        rename(SAMPLE = 1) |>
        transmute(SAMPLE, TEMPO_QC_STATUS = Status, TEMPO_QC_REASON = Reason)
}

#
# MAF summaries. Mutation class uses the pyrimidine reference
# (C>A, C>G, C>T, T>A, T>C, T>G); Ref_Tri gives the trinucleotide
# context for the 96-channel spectrum.
#
maf_cols <- c(
    "Hugo_Symbol", "Variant_Classification", "Variant_Type", "Reference_Allele",
    "Tumor_Seq_Allele2", "t_depth", "t_alt_count", "n_depth", "n_alt_count",
    "FILTER", "Ref_Tri", "Hotspot", "oncogenic", "t_var_freq"
)

revcomp <- function(x) {
    x |> chartr(old = "ACGT", new = "TGCA") |> stringi::stri_reverse()
}

read_maf <- function(file) {
    read_tsv_quiet(file, comment = "#", col_types = cols(.default = "c"), col_select = any_of(maf_cols)) |>
        mutate(across(c(t_depth, t_alt_count, n_depth, n_alt_count), as.numeric)) |>
        mutate(
            VAF = t_alt_count / t_depth,
            NVAF = n_alt_count / n_depth,
            flip = Variant_Type == "SNP" & Reference_Allele %in% c("A", "G"),
            SUB = case_when(
                Variant_Type != "SNP" ~ NA_character_,
                flip ~ str_c(revcomp(Reference_Allele), ">", revcomp(Tumor_Seq_Allele2)),
                TRUE ~ str_c(Reference_Allele, ">", Tumor_Seq_Allele2)
            ),
            CONTEXT = case_when(
                Variant_Type != "SNP" | is.na(Ref_Tri) ~ NA_character_,
                flip ~ revcomp(Ref_Tri),
                TRUE ~ Ref_Tri
            ),
            CHANNEL = if_else(is.na(CONTEXT), NA_character_,
                              str_c(str_sub(CONTEXT, 1, 1), "[", SUB, "]", str_sub(CONTEXT, 3, 3)))
        )
}

summarize_maf <- function(maf, pair, prefix) {
    snv <- maf |> filter(Variant_Type == "SNP")
    ti <- sum(snv$SUB %in% c("C>T", "T>C"))
    nonSyn <- c(
        "Missense_Mutation", "Nonsense_Mutation", "Frame_Shift_Del", "Frame_Shift_Ins",
        "In_Frame_Del", "In_Frame_Ins", "Splice_Site", "Nonstop_Mutation", "Translation_Start_Site"
    )
    subFrac <- c("C>A", "C>G", "C>T", "T>A", "T>C", "T>G") |>
        set_names(\(x) str_c("FRAC_", str_replace(x, ">", "to"))) |>
        map_dbl(\(s) if (nrow(snv) > 0) mean(snv$SUB == s) else NA_real_)
    tibble(
        PAIR = pair,
        N = nrow(maf),
        N_SNV = nrow(snv),
        N_DNP_ONP = sum(maf$Variant_Type %in% c("DNP", "TNP", "ONP")),
        N_INS = sum(maf$Variant_Type == "INS"),
        N_DEL = sum(maf$Variant_Type == "DEL"),
        N_NONSYN = sum(maf$Variant_Classification %in% nonSyn),
        N_SILENT = sum(maf$Variant_Classification == "Silent"),
        TI_TV = if (nrow(snv) > ti) ti / (nrow(snv) - ti) else NA_real_,
        MEDIAN_VAF = median(maf$VAF, na.rm = TRUE),
        FRAC_VAF_LT_05 = mean(maf$VAF < 0.05, na.rm = TRUE),
        FRAC_VAF_LT_10 = mean(maf$VAF < 0.10, na.rm = TRUE),
        MEDIAN_T_DEPTH = median(maf$t_depth, na.rm = TRUE),
        MEDIAN_N_DEPTH = median(maf$n_depth, na.rm = TRUE),
        MAX_NORMAL_VAF = suppressWarnings(max(maf$NVAF, na.rm = TRUE)),
        N_HOTSPOT = sum(maf$Hotspot %in% c("TRUE", "True", "1"), na.rm = TRUE),
        N_ONCOGENIC = sum(str_detect(maf$oncogenic %|% "", "Oncogenic"), na.rm = TRUE),
        !!!as.list(subFrac)
    ) |>
        mutate(MAX_NORMAL_VAF = if_else(is.finite(MAX_NORMAL_VAF), MAX_NORMAL_VAF, NA_real_)) |>
        rename_with(\(x) str_c(prefix, x), -PAIR)
}

`%|%` <- function(x, y) if_else(is.na(x), y, x)

maf_spectrum <- function(maf, pair) {
    maf |>
        filter(!is.na(CHANNEL)) |>
        count(CHANNEL, name = "COUNT") |>
        mutate(PAIR = pair, .before = 1)
}

maf_filter_counts <- function(maf, pair) {
    maf |>
        mutate(FILTER = replace_na(FILTER, "NA")) |>
        separate_longer_delim(FILTER, ";") |>
        count(FILTER, name = "COUNT") |>
        mutate(PAIR = pair, .before = 1)
}

#
# Manta: count of PASS SV records
#
read_manta_count <- function(file) {
    recs <- read_lines(file, progress = FALSE) |> str_subset("^#", negate = TRUE)
    filt <- str_split_i(recs, "\t", 7)
    tibble(
        PAIR = sample_from_path(file, "\\.manta\\.vcf\\.gz$"),
        MANTA_N_SV = len(recs),
        MANTA_N_SV_PASS = sum(filt == "PASS")
    )
}

#
# Nextflow trace: per-task rows; realtime and peak_rss are converted to
# hours and GB
#
parse_duration_h <- function(x) {
    x <- str_trim(x)
    part <- function(u) {
        v <- str_match(x, glue("([0-9.]+){u}(?![a-z])"))[, 2] |> as.numeric()
        replace_na(v, 0)
    }
    secs <- part("d") * 86400 + part("h") * 3600 + part("m") * 60 + part("s") + part("ms") / 1000
    if_else(x %in% c("-", ""), NA_real_, secs / 3600)
}

parse_mem_gb <- function(x) {
    v <- str_match(x, "([0-9.]+)\\s*([KMGT]?B)")
    mult <- c(B = 1 / 1024^3, KB = 1 / 1024^2, MB = 1 / 1024, GB = 1, TB = 1024)
    as.numeric(v[, 2]) * unname(mult[v[, 3]])
}

read_trace <- function(file) {
    read_tsv_quiet(file, col_types = cols(.default = "c")) |>
        mutate(
            PROCESS = str_remove(name, " \\(.*$"),
            REALTIME_H = parse_duration_h(realtime),
            PEAK_RSS_GB = parse_mem_gb(peak_rss),
            TRACE_FILE = basename(file)
        )
}
