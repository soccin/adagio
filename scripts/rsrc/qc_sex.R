#
# qc_sex.R
#
# Sex check for qcReport02.R, from Alfred's chromosome map: the reads on
# ChrX and ChrY, observed/expected (a chromosome's share of the mapped
# reads over its share of the genome). Needs qc_plots.R.
#
# The call is made on the normal: ChrY >= SEX_Y_PRESENT with ChrX <=
# SEX_X_MALE_MAX is male; ChrY below SEX_Y_PRESENT with ChrX >=
# SEX_X_FEMALE_MIN is female; anything else is unclear (e.g. XXY, X0, or
# DNA of two people). The tumor is checked against its normal on ChrY
# only: tumor ChrX moves with copy number.
#
# Thresholds from the WES IDT v2 QC background (qcdb 261123b, 400
# samples, 2026-11-24): ChrY in female samples 0.007-0.023, in male
# normals 0.15-0.72, in male tumors 0.07-1.08; ChrX in male normals
# 0.41-0.48, in female normals 0.77-0.92, in female tumors 0.51-0.98.
# All 200 background pairs agree on ChrY.
#
SEX_Y_PRESENT <- 0.05
SEX_X_MALE_MAX <- 0.6
SEX_X_FEMALE_MIN <- 0.7
SEX_METRICS <- c(X = "ALFRED_CHRX_OBS_EXP", Y = "ALFRED_CHRY_OBS_EXP")

#
# Reported sex from the project's sample metadata
# (meta/*_metadata_samples.csv, columns sampleName or
# investigatorSampleId, and sex): SAMPLE, REPORTED (Male, Female). Empty
# when there is no such file. A sample with conflicting values gets NA.
#
read_reported_sex <- function(metaDir = "meta") {
    empty <- tibble(SAMPLE = character(), REPORTED = character())
    if (!fs::dir_exists(metaDir)) return(empty)
    files <- fs::dir_ls(metaDir, regexp = "_metadata_samples\\.csv$")
    if (len(files) == 0) return(empty)
    meta <- files |>
        map(\(f) read_csv(f, col_types = cols(.default = "c"), show_col_types = FALSE, progress = FALSE)) |>
        list_rbind()
    if (!"sex" %in% names(meta)) return(empty)
    meta |>
        select(any_of(c("sampleName", "investigatorSampleId")), sex) |>
        pivot_longer(-sex, values_to = "SAMPLE") |>
        filter(!is.na(SAMPLE)) |>
        mutate(REPORTED = case_when(
            str_detect(str_to_upper(sex), "^M") ~ "Male",
            str_detect(str_to_upper(sex), "^F") ~ "Female"
        )) |>
        filter(!is.na(REPORTED)) |>
        summarize(REPORTED = if (n_distinct(REPORTED) == 1) REPORTED[1] else NA_character_, .by = SAMPLE)
}

# ChrX and ChrY of each sample (SAMPLE, TYPE, X, Y) from a wide table of
# metrics; NA when the Alfred columns are missing
sex_xy <- function(wide) {
    col_or_na <- \(col) if (col %in% names(wide)) wide[[col]] else rep(NA_real_, nrow(wide))
    tibble(SAMPLE = wide$SAMPLE, TYPE = wide$TYPE, X = col_or_na(SEX_METRICS[["X"]]),
           Y = col_or_na(SEX_METRICS[["Y"]]))
}

call_normal_sex <- function(x, y) {
    case_when(
        is.na(x) | is.na(y) ~ "No data",
        y >= SEX_Y_PRESENT & x <= SEX_X_MALE_MAX ~ "Male",
        y < SEX_Y_PRESENT & x >= SEX_X_FEMALE_MIN ~ "Female",
        .default = "Unclear"
    )
}

#
# One row per pair: ChrX and ChrY of tumor and normal (XT, YT, XN, YN),
# reported sex (REPORTED: the normal's, else the tumor's), the call from
# the normal (CALL), the Conpair concordance (from concord: PAIR,
# CONCORDANCE, CONCORD_LEVEL), and STATUS: "OK" or the problems found.
# Problems first.
#
sex_table <- function(xy, pairing, reported, concord) {
    tbl <- pairing |>
        select(PAIR, TUMOR_ID, NORMAL_ID) |>
        left_join(xy |> select(TUMOR_ID = SAMPLE, XT = X, YT = Y), by = "TUMOR_ID") |>
        left_join(xy |> select(NORMAL_ID = SAMPLE, XN = X, YN = Y), by = "NORMAL_ID") |>
        left_join(reported |> select(TUMOR_ID = SAMPLE, REP_T = REPORTED), by = "TUMOR_ID") |>
        left_join(reported |> select(NORMAL_ID = SAMPLE, REP_N = REPORTED), by = "NORMAL_ID") |>
        left_join(concord, by = "PAIR") |>
        mutate(REPORTED = coalesce(REP_N, REP_T), CALL = call_normal_sex(XN, YN))
    problems <- tbl |>
        transmute(
            NO_DATA = if_else(CALL == "No data", "no Alfred data for the normal", NA),
            UNCLEAR = if_else(CALL == "Unclear", "normal sex unclear", NA),
            REP_DIFF = if_else(!is.na(REP_T) & !is.na(REP_N) & REP_T != REP_N,
                               "reported sex differs between tumor and normal", NA),
            REP_CALL = if_else(!is.na(REPORTED) & CALL %in% c("Male", "Female") & REPORTED != CALL,
                               str_c("reported ", str_to_lower(REPORTED), ", called ", str_to_lower(CALL)), NA),
            T_NO_DATA = if_else(is.na(YT), "no Alfred data for the tumor", NA),
            T_HAS_Y = if_else(CALL == "Female" & YT >= SEX_Y_PRESENT, "tumor has ChrY, normal female", NA),
            T_NO_Y = if_else(CALL == "Male" & YT < SEX_Y_PRESENT, "tumor lacks ChrY: loss of Y or a swap", NA)
        )
    tbl |>
        mutate(STATUS = pmap_chr(problems, \(...) {
            p <- na.omit(c(...))
            if (len(p) == 0) "OK" else str_c(p, collapse = "; ")
        })) |>
        arrange(STATUS == "OK", TUMOR_ID) |>
        select(-REP_T, -REP_N)
}

#
# ChrY (log) against ChrX: the background in grey, the project samples
# as points; samples of pairs with a problem are labeled. fillTypes: the
# types in the page legend.
#
sex_plot <- function(bgXY, projXY, labelSamples, fillTypes) {
    floorY <- 0.004
    bgXY <- bgXY |> filter(is.finite(X), is.finite(Y)) |> mutate(Y = pmax(Y, floorY))
    projXY <- projXY |>
        filter(is.finite(X), is.finite(Y)) |>
        mutate(Y = pmax(Y, floorY), TYPE = factor(TYPE, levels = fillTypes))
    ggplot(mapping = aes(X, Y)) +
        geom_hline(yintercept = SEX_Y_PRESENT, linetype = "22", colour = "grey40", linewidth = 0.4) +
        geom_point(data = bgXY, colour = "grey60", size = 1.1, alpha = 0.5) +
        geom_point(data = projXY, aes(fill = TYPE), shape = 21, colour = "black", stroke = 0.5, size = 2.2,
                   show.legend = TRUE) +
        geom_label_repel(
            data = projXY |> filter(SAMPLE %in% labelSamples),
            aes(label = SAMPLE),
            size = 2.6, fontface = "bold", fill = "white", label.size = 0.3, box.padding = 0.5,
            min.segment.length = 0, segment.colour = "grey30", max.overlaps = Inf, seed = 1
        ) +
        scale_fill_manual(values = TYPE_COLORS, limits = fillTypes, drop = FALSE, name = "Project samples") +
        scale_y_log10(breaks = c(0.005, 0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1)) +
        labs(title = "Sex: ChrY vs ChrX reads, observed/expected", x = "ChrX", y = "ChrY (log scale)") +
        qc_theme(11, 10) +
        theme(panel.grid.major.x = element_line(colour = "grey88", linewidth = 0.3))
}

sex_rules_text <- function() {
    str_c(
        "Sex call, from the normal:",
        glue("  male: ChrY >= {SEX_Y_PRESENT} and ChrX <= {SEX_X_MALE_MAX}"),
        glue("  female: ChrY < {SEX_Y_PRESENT} and ChrX >= {SEX_X_FEMALE_MIN}"),
        "  anything else: unclear (XXY, X0, two people's DNA)",
        "The tumor is checked against its normal on ChrY",
        "only: tumor ChrX changes with copy number.",
        "",
        "Grey: the QC background. Dashed line: ChrY",
        glue("= {SEX_Y_PRESENT}. A male tumor without ChrY is loss of Y"),
        "or a swap; the Conpair concordance tells which.",
        "Reported: meta/*_metadata_samples.csv.",
        sep = "\n"
    )
}
