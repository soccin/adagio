#
# qc_metric_info.R
#
# Per-metric information for the QC report (qcReport02.R): units, the
# display name, the bad side, and the background median and robust SD
# of the bad-sample rule (see background_stats).
#
# Percentages (fractions and 0-100 values) are judged in log-odds space:
# median and robust SD of logit(p) over the background, and the limits
# mapped back to percent. Other metrics use the values as they are.
#

Z_FLAG <- 3
PERCENT_KINDS <- c("frac", "pct100")
LOGIT_EPS <- 1e-6

logit <- function(p) {
    p <- pmin(pmax(p, LOGIT_EPS), 1 - LOGIT_EPS)
    log(p / (1 - p))
}

inv_logit <- function(x) 1 / (1 + exp(-x))

#
# Metrics derived from pairs of database metrics. Each new metric is
# log(numerator / denominator) per sample; the source metrics in DROP
# are removed, so only the derived metric is plotted and scanned.
#
# Strand balance: the forward and reverse fractions of mapped reads add
# to 1, so plotting both shows the same thing twice; log(F/R) is 0 for
# a balanced sample.
#
DERIVED_METRICS <- list(
    ALFRED_STRAND_LOG_RATIO = list(
        num = "ALFRED_MAPPEDFORWARDFRACTION",
        den = "ALFRED_MAPPEDREVERSEFRACTION",
        drop = c("ALFRED_MAPPEDFORWARDFRACTION", "ALFRED_MAPPEDREVERSEFRACTION",
                 "ALFRED_N_MAPPEDFORWARD", "ALFRED_N_MAPPEDREVERSE")
    )
)

# long: one row per sample and metric, with columns idCols, METRIC, VALUE
add_derived_metrics <- function(long, idCols) {
    derived <- imap(DERIVED_METRICS, \(d, name) {
        long |>
            filter(METRIC %in% c(d$num, d$den)) |>
            select(all_of(idCols), METRIC, VALUE) |>
            pivot_wider(names_from = METRIC, values_from = VALUE) |>
            filter(if_all(c(d$num, d$den), \(x) !is.na(x))) |>
            transmute(across(all_of(idCols)), METRIC = name, VALUE = log(.data[[d$num]] / .data[[d$den]]))
    }) |>
        bind_rows()
    dropped <- DERIVED_METRICS |>
        map("drop") |>
        unlist()
    long |>
        filter(!METRIC %in% dropped) |>
        bind_rows(derived)
}

#
# Units of a metric, from its name and values:
#   pct100  percent on a 0-100 scale (Qualimap percentages, Conpair
#           concordance, Picard AT/GC dropout); divided by 100 to plot
#   frac    fraction 0-1
#   bp      insert size
#   cov     coverage depth
#   count   large whole numbers
#   number  anything else
#
metric_kind <- function(metric, values) {
    v <- values[is.finite(values)]
    isPct100 <- str_detect(metric, "^QUALIMAP_.*(_PCT$|PERCENTAGE)|^QUALIMAP_PCT_") ||
        metric %in% c("CONPAIR_CONCORDANCE", "HSM_AT_DROPOUT", "HSM_GC_DROPOUT")
    if (isPct100) return("pct100")
    if (str_detect(metric, "PCT|FRAC|RATE|CONTAMINATION|ON_TARGET|_VS_SELECTED|EFFICIENCY") &&
        all(v >= 0 & v <= 1)) return("frac")
    if (str_detect(metric, "INSERT_?SIZE") && !str_detect(metric, "UNKNOWN")) return("bp")
    if (str_detect(metric, "COV") && !str_detect(metric, "NORM|FRAC|PCT|ZERO|CVG")) return("cov")
    if (all(v == round(v)) && max(abs(v)) >= 1e4) return("count")
    "number"
}

#
# Display name built from a column name, for metrics not in
# metricInfo.tsv: the tool prefix is dropped, run-together Alfred names
# are split into words, abbreviations are expanded, and percent and
# fraction words become a leading "%".
#
LABEL_WORDS <- c(
    EXC = "Excluded", DUPE = "Duplicates", CVG = "Coverage", COV = "Coverage", COVERAGEDATA = "Coverage",
    NORM = "Normalized", LT = "Below", GT = "Above", GE = "at Least", PF = "Passing Filter", UQ = "Unique",
    HS = "Hybrid Selection", OBS = "Observed", EXP = "Expected", MAPQ = "Mapping Quality",
    BASEQ = "Base Quality", EXT = "Extension", CHRX = "ChrX", CHRY = "ChrY", QCFAIL = "QC Fail",
    SAMECHR = "Same Chromosome", BED = "Targets", DEL = "Deletions", INS = "Insertions", BP = "bp",
    VS = "vs", TO = "to", IN = "in", OVER = "over", OF = "of", AND = "and", N = "N", SD = "SD",
    IQR = "IQR", GC = "GC", AT = "AT", SNP = "SNP", ACTG = "ACTG", Q20 = "Q20", Q30 = "Q30",
    HET = "Het", INDELS = "Indels", READ1 = "Read 1", READ2 = "Read 2"
)
PERCENT_WORDS <- c("PCT", "FRAC", "FRACTION", "PERCENTAGE")
SPLIT_WORDS <- c(
    "QCFAIL", "DUPLICATE", "UNMAPPED", "MAPPED", "FORWARD", "REVERSE", "FRACTION", "SECONDARY",
    "SUPPLEMENTARY", "SPLICED", "ALIGNMENTS", "ALIGNMENT", "ALIGNED", "PAIRS", "SAMECHR", "PROPER",
    "MISMATCH", "MATCH", "DELETION", "INSERTION", "HOMOPOLYMER", "CONTEXT", "DEL", "INS", "SOFTCLIP",
    "HARDCLIP", "ERROR", "RATE", "RATIO", "MEDIAN", "INSERT", "SIZE", "COVERAGEDATA", "COVERAGE",
    "COVERED", "COV", "BP", "SD", "MAPQ", "ENRICHMENT", "OVER", "IN", "BED", "VS", "TO"
)
SPLIT_WORDS <- SPLIT_WORDS[order(-nchar(SPLIT_WORDS))]

# Split a run-together token into dictionary words (longest match
# first); digits and a lone N are allowed between words. Tokens that do
# not split completely are returned whole.
split_token <- function(token) {
    if (token %in% c(names(LABEL_WORDS), PERCENT_WORDS) || nchar(token) <= 3) return(token)
    parts <- character()
    rest <- token
    while (nchar(rest) > 0) {
        hit <- SPLIT_WORDS[str_starts(rest, fixed(SPLIT_WORDS))][1]
        if (is.na(hit)) hit <- str_extract(rest, "^([0-9]+|N)")
        if (is.na(hit)) return(token)
        parts <- c(parts, hit)
        rest <- str_sub(rest, nchar(hit) + 1)
    }
    parts
}

auto_metric_label <- function(metric) {
    name <- metric |>
        str_remove("^(HSM|ALFRED|FASTP|CONPAIR)_")
    if (str_starts(metric, "QUALIMAP_")) {
        name <- name |>
            str_remove("^QUALIMAP_") |>
            str_remove("^(GLOBALS|ACTG_CONTENT|MISMATCHES_AND_INDELS|MAPPING_QUALITY|INSERT_SIZE|COVERAGE|REFERENCE)_(?=.)")
    }
    words <- str_split_1(name, "_") |>
        map(split_token) |>
        unlist()
    isPercent <- any(words %in% PERCENT_WORDS)
    words <- words[!words %in% PERCENT_WORDS]
    words <- map_chr(words, \(w) {
        if (w %in% names(LABEL_WORDS)) return(LABEL_WORDS[[w]])
        if (str_detect(w, "^[0-9.]+X?$")) return(w)
        str_to_title(w)
    })
    str_c(c(if (isPercent) "%", words), collapse = " ")
}

read_metric_table <- function(file) {
    tbl <- read_tsv(file, comment = "#", col_types = cols(.default = "c"), show_col_types = FALSE)
    badValues <- setdiff(unique(tbl$BAD), c("low", "high", "both"))
    if (len(badValues) > 0) {
        stop(glue("{file}: BAD must be low, high or both, not {str_c(badValues, collapse = ', ')}"), call. = FALSE)
    }
    tbl
}

#
# One row per metric: KIND, SCALE_BY (100 for 0-100 values), ZSPACE
# (logit for percentages, linear otherwise), BAD and LABEL
#
metric_info <- function(bgLong, projLong, tableFile) {
    tbl <- read_metric_table(tableFile)
    bind_rows(
        bgLong |> select(METRIC, VALUE),
        projLong |> select(METRIC, VALUE)
    ) |>
        filter(is.finite(VALUE)) |>
        summarize(KIND = metric_kind(METRIC[1], VALUE), .by = METRIC) |>
        mutate(
            SCALE_BY = if_else(KIND == "pct100", 100, 1),
            ZSPACE = if_else(KIND %in% PERCENT_KINDS, "logit", "linear")
        ) |>
        left_join(tbl, by = "METRIC") |>
        mutate(
            BAD = coalesce(BAD, "both"),
            LABEL = coalesce(LABEL, map_chr(METRIC, auto_metric_label))
        )
}

to_z_space <- function(value, zspace, scaleBy) {
    if_else(zspace == "logit", logit(value / scaleBy), value)
}

from_z_space <- function(x, zspace, scaleBy) {
    if_else(zspace == "logit", inv_logit(x) * scaleBy, x)
}

#
# Background center and spread per metric and type, in z space, and the
# Z_FLAG limits in the metric's own units. Robust, to match the box
# plots: center MU = median; spread SIGMA = MAD_TO_SD x the mean absolute
# deviation from the median (1.2533 = sqrt(pi/2) makes it estimate the
# SD for normal data).
#
MAD_TO_SD <- 1.2533

background_stats <- function(bgLong, info) {
    bgLong |>
        inner_join(info |> select(METRIC, ZSPACE, SCALE_BY, BAD), by = "METRIC") |>
        mutate(ZV = to_z_space(VALUE, ZSPACE, SCALE_BY)) |>
        summarize(
            MU = median(ZV),
            SIGMA = MAD_TO_SD * mean(abs(ZV - median(ZV))),
            MEDIAN = median(VALUE),
            MIN = min(VALUE),
            .by = c(METRIC, TYPE, ZSPACE, SCALE_BY, BAD)
        ) |>
        mutate(
            LOW = from_z_space(MU - Z_FLAG * SIGMA, ZSPACE, SCALE_BY),
            HIGH = from_z_space(MU + Z_FLAG * SIGMA, ZSPACE, SCALE_BY)
        )
}

#
# The limits on the bad side, for the dotted lines. A limit below
# zero for a metric that is never negative is dropped.
#
limit_lines <- function(stats) {
    stats |>
        filter(is.finite(SIGMA), SIGMA > 0) |>
        pivot_longer(c(LOW, HIGH), names_to = "SIDE", values_to = "LIMIT") |>
        filter(
            (SIDE == "LOW" & BAD %in% c("low", "both")) | (SIDE == "HIGH" & BAD %in% c("high", "both")),
            !(MIN >= 0 & LIMIT < 0)
        ) |>
        select(METRIC, TYPE, SIDE, LIMIT)
}

#
# z of each project value against the background of its type, and
# IS_BAD: beyond Z_FLAG on the bad side
#
score_project <- function(projLong, stats) {
    projLong |>
        left_join(
            stats |> select(METRIC, TYPE, ZSPACE, SCALE_BY, BAD, MU, SIGMA, MEDIAN, LOW, HIGH),
            by = c("METRIC", "TYPE")
        ) |>
        mutate(
            Z = if_else(is.finite(SIGMA) & SIGMA > 0, (to_z_space(VALUE, ZSPACE, SCALE_BY) - MU) / SIGMA, NA_real_),
            IS_BAD = coalesce(
                (BAD %in% c("low", "both") & Z < -Z_FLAG) | (BAD %in% c("high", "both") & Z > Z_FLAG),
                FALSE
            )
        )
}
