#
# qc_metric_info.R
#
# Per-metric information for the QC report (qcReport02.R): units, the
# display name, the bad side, and the background percentiles of the
# WARN and FAIL rule (see background_stats).
#
# A project value is WARN beyond the background 95th percentile of its
# type on the bad side and FAIL beyond the 99th: below the 5th / 1st
# percentile for metrics bad when low, above the 95th / 99th for
# metrics bad when high. Metrics bad on both sides use the central
# intervals: outside 2.5-97.5% WARN, outside 0.5-99.5% FAIL.
#
# The Conpair metrics have fixed limits instead (FIXED_LIMITS below).
#
# The robust z (median and robust SD, in log-odds space for
# percentages) only ranks flagged cases; it does not flag them.
#

WARN_PCT <- 0.95
FAIL_PCT <- 0.99

# 0.95 -> "95th", for report text
pct_label <- function(p) str_c(100 * p, "th")

#
# Metrics judged against fixed limits instead of background
# percentiles, in the metric's own units (contamination is a fraction,
# concordance 0-100); NA: no limit. A value at a high limit is flagged
# (contamination of exactly 2% is WARN); a value at a low limit is not.
# Contamination: Tempo's cutoffs. Concordance: a tumor and its normal
# come from one person, so below 95% is a FAIL; there is no WARN.
#
CONTAM_WARN <- 0.02
CONTAM_FAIL <- 0.05
CONCORD_FAIL <- 95
FIXED_LIMITS <- tribble(
    ~METRIC,                 ~WARN_LOW, ~FAIL_LOW,    ~WARN_HIGH,  ~FAIL_HIGH,
    "CONPAIR_CONTAMINATION", NA_real_,  NA_real_,     CONTAM_WARN, CONTAM_FAIL,
    "CONPAIR_CONCORDANCE",   NA_real_,  CONCORD_FAIL, NA_real_,    NA_real_
)

# For report text
fixed_limits_text <- function() {
    glue("contamination WARN from {100 * CONTAM_WARN}%, FAIL from {100 * CONTAM_FAIL}%; ",
         "tumor/normal concordance FAIL below {CONCORD_FAIL}%")
}
PERCENT_KINDS <- c("frac", "pct100")
LOGIT_EPS <- 1e-6

# Report text for values: percentages as percent (3 significant
# digits), everything else as a number (4)
format_num <- function(x, digits = 4) {
    map_chr(x, \(v) format(signif(v, digits), big.mark = ",", scientific = FALSE, trim = TRUE, drop0trailing = TRUE))
}

format_value <- function(x, kind, scaleBy) {
    if_else(kind %in% PERCENT_KINDS, str_c(format_num(100 * x / scaleBy, 3), "%"), format_num(x))
}

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
        str_remove("^(HSM|ASM|ALFRED|FASTP|CONPAIR)_")
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
# Background per metric and type: the WARN and FAIL limits (percentiles,
# see the top of this file), the median, and the robust center MU and
# spread SIGMA in z space for ranking: MU = median, SIGMA = MAD_TO_SD x
# the mean absolute deviation from the median (1.2533 = sqrt(pi/2) makes
# it estimate the SD for normal data). VALUES keeps the sorted values for
# the percentile of each project value. FIXED: the limits come from
# FIXED_LIMITS.
#
MAD_TO_SD <- 1.2533

# Lower-tail probability of the limit on each side: one-sided for low
# or high, central interval for both
tail_prob <- function(pct, bad) if_else(bad == "both", (1 - pct) / 2, 1 - pct)

background_stats <- function(bgLong, info) {
    bgLong |>
        inner_join(info |> select(METRIC, ZSPACE, SCALE_BY, BAD), by = "METRIC") |>
        mutate(ZV = to_z_space(VALUE, ZSPACE, SCALE_BY)) |>
        summarize(
            MU = median(ZV),
            SIGMA = MAD_TO_SD * mean(abs(ZV - median(ZV))),
            MEDIAN = median(VALUE),
            WARN_LOW = quantile(VALUE, tail_prob(WARN_PCT, BAD[1]), names = FALSE),
            WARN_HIGH = quantile(VALUE, 1 - tail_prob(WARN_PCT, BAD[1]), names = FALSE),
            FAIL_LOW = quantile(VALUE, tail_prob(FAIL_PCT, BAD[1]), names = FALSE),
            FAIL_HIGH = quantile(VALUE, 1 - tail_prob(FAIL_PCT, BAD[1]), names = FALSE),
            VALUES = list(sort(VALUE)),
            .by = c(METRIC, TYPE, ZSPACE, SCALE_BY, BAD)
        ) |>
        left_join(FIXED_LIMITS |> rename_with(\(n) str_c(n, "_FIXED"), -METRIC), by = "METRIC") |>
        mutate(
            FIXED = METRIC %in% FIXED_LIMITS$METRIC,
            WARN_LOW = if_else(FIXED, WARN_LOW_FIXED, WARN_LOW),
            WARN_HIGH = if_else(FIXED, WARN_HIGH_FIXED, WARN_HIGH),
            FAIL_LOW = if_else(FIXED, FAIL_LOW_FIXED, FAIL_LOW),
            FAIL_HIGH = if_else(FIXED, FAIL_HIGH_FIXED, FAIL_HIGH)
        ) |>
        select(-ends_with("_FIXED"))
}

#
# The limits on the bad side, for the short vertical lines: LEVEL WARN
# or FAIL, LIMIT. None for a background with no spread, unless the
# limits are fixed.
#
limit_lines <- function(stats) {
    stats |>
        filter(FIXED | (is.finite(SIGMA) & SIGMA > 0)) |>
        pivot_longer(c(WARN_LOW, WARN_HIGH, FAIL_LOW, FAIL_HIGH), names_to = c("LEVEL", "SIDE"),
                     names_sep = "_", values_to = "LIMIT") |>
        filter(
            !is.na(LIMIT),
            (SIDE == "LOW" & BAD %in% c("low", "both")) | (SIDE == "HIGH" & BAD %in% c("high", "both"))
        ) |>
        select(METRIC, TYPE, LEVEL, SIDE, LIMIT)
}

#
# Each project value against the background of its type: LEVEL (FAIL,
# WARN or NA) on the bad side, LIMIT (the limit crossed), PCTILE (the
# fraction of the background at or below the value), and Z for ranking.
# IS_BAD: LEVEL is FAIL or WARN. No flags when the background has no
# spread, unless the limits are fixed. A value at a fixed high limit is
# flagged.
#
score_project <- function(projLong, stats) {
    projLong |>
        left_join(
            stats |> select(METRIC, TYPE, ZSPACE, SCALE_BY, BAD, MU, SIGMA, MEDIAN,
                            WARN_LOW, WARN_HIGH, FAIL_LOW, FAIL_HIGH, FIXED, VALUES),
            by = c("METRIC", "TYPE")
        ) |>
        mutate(
            FIXED = coalesce(FIXED, FALSE),
            SPREAD = is.finite(SIGMA) & SIGMA > 0,
            Z = if_else(SPREAD, (to_z_space(VALUE, ZSPACE, SCALE_BY) - MU) / SIGMA, NA_real_),
            LOW_SIDE = BAD %in% c("low", "both"),
            HIGH_SIDE = BAD %in% c("high", "both"),
            OVER_FAIL = if_else(FIXED, VALUE >= FAIL_HIGH, VALUE > FAIL_HIGH),
            OVER_WARN = if_else(FIXED, VALUE >= WARN_HIGH, VALUE > WARN_HIGH),
            LEVEL = case_when(
                !(SPREAD | FIXED) | is.na(VALUE) ~ NA_character_,
                LOW_SIDE & VALUE < FAIL_LOW ~ "FAIL",
                HIGH_SIDE & OVER_FAIL ~ "FAIL",
                LOW_SIDE & VALUE < WARN_LOW ~ "WARN",
                HIGH_SIDE & OVER_WARN ~ "WARN"
            ),
            LIMIT = case_when(
                LEVEL == "FAIL" & VALUE < FAIL_LOW ~ FAIL_LOW,
                LEVEL == "FAIL" ~ FAIL_HIGH,
                LEVEL == "WARN" & VALUE < WARN_LOW ~ WARN_LOW,
                LEVEL == "WARN" ~ WARN_HIGH
            ),
            PCTILE = map2_dbl(VALUES, VALUE, \(b, v) if (is.null(b) || is.na(v)) NA_real_ else mean(b <= v)),
            IS_BAD = !is.na(LEVEL)
        ) |>
        select(-VALUES, -SPREAD, -LOW_SIDE, -HIGH_SIDE, -OVER_FAIL, -OVER_WARN)
}
