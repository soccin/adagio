#
# qc_glossary.R
#
# Glossary page for the summary QC report (qcReport02.R): the terms and
# marks used in the report, with this run's limits. Needs
# qc_metric_info.R, qc_plots.R and qc_sex.R.
#
# The layout is the one of the glossary page of the Conpair cohort
# report (soccin/BAMQC, conpair/bin/conpairReport.R), for a portrait
# page: the entries flow down two columns of balanced height, so no line
# runs across the page; an entry is never split, and a section heading
# always has its first entry under it. Text is wrapped by its measured
# width, so the page must be built while the PDF device is open:
# glossary_page() returns a function that builds it (see write_pdf in
# qcReport02.R). Text is set smaller if it would not fit.
#

GLOSSARY_FONT <- 9
GLOSSARY_MIN_FONT <- 7
# Page body: columns, width and height in inches. Portrait for the
# summary report (8.5 x 11 in), landscape legal for the per-pair pages
# (14 x 8.5 in)
GLOSSARY_PORTRAIT <- list(columns = 2, width = 7.6, height = 9.6)
GLOSSARY_LANDSCAPE <- list(columns = 4, width = 13.1, height = 6.9)
GLOSSARY_GUTTER_IN <- 0.35
GLOSSARY_KEY_IN <- 0.4
KEY_SIDE_IN <- 0.12

# Bin of each item when the items are packed in order into bins of the
# given capacity: words onto lines, entries into columns. An item that
# does not fit starts the next bin, and the separator before it is
# dropped there; an item larger than a bin gets a bin of its own.
fill_bins <- function(sizes, capacity, seps = 0) {
    seps <- rep_len(seps, len(sizes))
    accumulate(seq_along(sizes), \(acc, k) {
        if (acc[2] > 0 && acc[2] + seps[k] + sizes[k] > capacity) {
            c(acc[1] + 1, sizes[k])
        } else {
            c(acc[1], acc[2] + (acc[2] > 0) * seps[k] + sizes[k])
        }
    }, .init = c(1, 0))[-1] |>
        map_dbl(1)
}

#
# Keys: small copies of the marks the report draws
#

# Points as ggplot2 draws them with this shape, size and stroke, at x
# (npc) across the key
key_points <- function(shape, size, color, fill = NA, stroke = 0.5, x = 0.5, alpha = 1) {
    grid::pointsGrob(x, rep(0.5, len(x)), pch = shape, size = grid::unit(1, "char"),
                     gp = grid::gpar(col = scales::alpha(color, alpha), fill = fill,
                                     fontsize = size * .pt + stroke * .stroke / 2,
                                     lwd = stroke * .stroke / 2))
}

# A limit line of each level: the grey line with the dotted colored line
# on top, as in the panels
key_limits <- function(levels) {
    x <- seq(0.3, 0.7, length.out = len(levels))
    grid::gTree(children = grid::gList(
        grid::segmentsGrob(x, 0, x, 1, gp = grid::gpar(col = LIMIT_BASE_COLOR, lwd = LIMIT_WIDTH * .pt)),
        grid::segmentsGrob(x, 0, x, 1, gp = grid::gpar(col = unname(LEVEL_COLORS[levels]),
                                                         lwd = LIMIT_WIDTH * .pt, lty = "11"))
    ))
}

# A background box as in the panels: whiskers, box and median
key_box <- function() {
    grid::gTree(children = grid::gList(
        grid::segmentsGrob(0.05, 0.5, 0.95, 0.5, gp = grid::gpar(col = "grey65", lwd = 0.8)),
        grid::rectGrob(x = 0.5, width = 0.45, height = 0.7,
                       gp = grid::gpar(fill = scales::alpha("grey60", 0.3), col = "grey65", lwd = 0.8)),
        grid::segmentsGrob(0.45, 0.15, 0.45, 0.85, gp = grid::gpar(col = "grey65", lwd = 1.2))
    ))
}

# A sample label as in the panels
key_label <- function() {
    grid::gTree(children = grid::gList(
        grid::roundrectGrob(width = 0.8, height = 0.9, r = grid::unit(0.1, "snpc"),
                            gp = grid::gpar(fill = "white", col = "black", lwd = 0.6)),
        grid::textGrob("ID", gp = grid::gpar(fontsize = 6, fontface = "bold"))
    ))
}

summary_glossary_keys <- function() {
    ring <- \(levels, x) key_points(21, 3.5, unname(LEVEL_COLORS[levels]), stroke = 1.2, x = x)
    list(
        ringFail = ring("FAIL", 0.5),
        ringWarn = ring("WARN", 0.5),
        rings = ring(c("WARN", "FAIL"), c(0.3, 0.7)),
        circles = key_points(21, 2, "black", fill = unname(TYPE_COLORS[c("Tumor", "Normal", "Pair")]),
                             x = c(0.2, 0.5, 0.8)),
        box = key_box(),
        label = key_label(),
        limits = key_limits(c("WARN", "FAIL")),
        greyDots = key_points(19, 1.1, "grey60", x = c(0.25, 0.5, 0.75), alpha = 0.5),
        dashed = grid::segmentsGrob(0.1, 0.5, 0.9, 0.5,
                                    gp = grid::gpar(col = "grey40", lty = "22", lwd = 0.4 * .pt))
    )
}

#
# The entries of the summary report's glossary: section, term, text, key
# (a name in summary_glossary_keys(), or NA). ctx: assay, version,
# seqTech, nTumor, nNormal, nPair (the background), typeLimited (key
# metrics judged in one type, e.g. "% Target Bases at 100X: tumors"),
# nScanned, xlsxName.
#
summary_glossary_entries <- function(ctx) {
    central <- \(p) str_c(100 * (1 - p) / 2, "-", 100 * (1 + p) / 2, "%")
    typeLimitedRows <- if (len(ctx$typeLimited) > 0) {
        tibble(
            section = "Metrics and pages",
            term = "(tumors only), (normals only)",
            text = glue("After a key metric's name: the metric is judged in one type only ",
                        "({str_c(ctx$typeLimited, collapse = '; ')}). The other type is left out of its panel ",
                        "and of the flags."),
            key = NA_character_
        )
    }
    bind_rows(
        tribble(
            ~section, ~term, ~text, ~key,
            "Flags", "FAIL",
            glue("Beyond the {pct_label(FAIL_PCT)} percentile of the background of the same type, on the bad ",
                 "side of the metric. Conpair metrics have fixed limits instead."),
            "ringFail",
            "Flags", "WARN",
            glue("Beyond the {pct_label(WARN_PCT)} percentile but not the {pct_label(FAIL_PCT)}, on the bad ",
                 "side. Conpair metrics have fixed limits instead."),
            "ringWarn",
            "Flags", "Bad side",
            glue("The side of a metric where values mean a problem: low (coverage), high (duplicates) or ",
                 "both. A metric bad on both sides is WARN outside the central {central(WARN_PCT)} of the ",
                 "background and FAIL outside {central(FAIL_PCT)}."),
            NA,
            "Flags", "Fixed limits",
            glue("Conpair limits that do not depend on the background: contamination WARN from ",
                 "{100 * CONTAM_WARN}%, FAIL from {100 * CONTAM_FAIL}% (Tempo's cutoffs); tumor/normal ",
                 "concordance FAIL below {CONCORD_FAIL}%, with no WARN."),
            NA,
            "Flags", "Percentile",
            "The percent of the background of the same type at or below the value.", NA,
            "Flags", "Robust z",
            str_c("The distance from the background median in robust standard deviations, on a log-odds ",
                  "scale for percentages. It orders the flagged cases; it does not flag them."),
            NA,
            "QC background", "QC background",
            glue("Samples of earlier {ctx$assay} projects, QC database version {ctx$version}. Only the ",
                 "{ctx$seqTech} samples are used: {ctx$nTumor} tumors, {ctx$nNormal} normals, and the ",
                 "{ctx$nPair} pairs whose tumor and normal both are {ctx$seqTech}."),
            NA,
            "QC background", "Sequencer technology",
            glue("From the instrument ID in the fastp file names ({seq_tech_rules()}). Many metrics ",
                 "differ between technologies, so a project is compared only with samples of its own. A ",
                 "project on more than one technology gets no report."),
            NA,
            "QC background", "Type",
            str_c("Tumor, normal or pair. Each value is compared with the background of its own type. ",
                  "Pair metrics (concordance) have one value per tumor/normal pair."),
            NA,
            "Metrics and pages", "Key metrics",
            "The metrics on the first pages, shown whether or not a sample is flagged. They are always scanned.",
            NA
        ),
        typeLimitedRows,
        tribble(
            ~section, ~term, ~text, ~key,
            "Metrics and pages", "Scanned metrics",
            glue("The {ctx$nScanned} metrics checked for flags: Picard hybrid selection and alignment ",
                 "summary metrics, duplicate fraction (Alfred), Q30 rate (fastp) and Conpair. Left out: ",
                 "metrics that repeat another (Spearman |rho| of 0.9 or more in tumors and in normals) and ",
                 "% target bases at depths other than the key ones."),
            NA,
            "Metrics and pages", "Other metrics with a FAIL",
            str_c("Scanned metrics other than the key metrics with at least one FAIL, worst first. A metric ",
                  "with only WARN cases is listed only in the flagged table."),
            NA,
            "Metrics and pages", "Flagged samples",
            glue("The table of every FAIL and WARN in the scanned metrics, FAIL first. Median: the ",
                 "background median. Limit: the limit crossed. *: a key metric. Also in {ctx$xlsxName}, ",
                 "with metric IDs and unrounded values."),
            NA,
            "Metrics and pages", "Log scale",
            "After a panel title: a log axis, for values spread over orders of magnitude or all below 10%.", NA,
            "Metrics and pages", "Log-odds axis",
            "After a panel title: an axis for percentages near 100% that spreads out 99%, 99.9% and 99.99%.", NA,
            "Concordance and sex", "Concordance",
            glue("Conpair, on each tumor and its normal: the percent of markers homozygous in the normal at ",
                 "which the tumor has the same genotype. One person: near 100%. Below {CONCORD_FAIL}%: FAIL, ",
                 "usually a sample swap or a labeling error."),
            NA,
            "Concordance and sex", "Contamination",
            glue("Conpair's estimate of the percent of a sample's DNA that comes from another person. ",
                 "Normal: from its own reads. Tumor: at the markers homozygous in its normal, so copy number ",
                 "changes do not affect it. WARN from {100 * CONTAM_WARN}%, FAIL from {100 * CONTAM_FAIL}%."),
            NA,
            "Concordance and sex", "Marker",
            "One of about 7,400 common SNPs (minor allele frequency at least 0.4) that Conpair genotypes.", NA,
            "Concordance and sex", "ChrX, ChrY",
            str_c("Alfred: the reads on the chromosome, observed/expected: its share of the mapped reads ",
                  "over its share of the genome. In the sex table, N is the normal and T the tumor."),
            NA,
            "Concordance and sex", "Called",
            glue("The sex called from the normal: male when ChrY is at least {SEX_Y_PRESENT} and ChrX at ",
                 "most {SEX_X_MALE_MAX}; female when ChrY is below {SEX_Y_PRESENT} and ChrX at least ",
                 "{SEX_X_FEMALE_MIN}; else unclear (XXY, X0, or DNA of two people). The tumor is checked ",
                 "against its normal on ChrY only: tumor ChrX changes with copy number."),
            NA,
            "Concordance and sex", "Reported",
            "The sex in the project's sample metadata (meta/*_metadata_samples.csv); - when not given.", NA,
            "Concordance and sex", "Status",
            str_c("OK, or each problem found: reported and called sex differ; tumor and normal reported ",
                  "differently; tumor lacks ChrY with a male normal; tumor has ChrY with a female normal; ",
                  "normal sex unclear; no Alfred data."),
            NA,
            "Concordance and sex", "Loss of Y",
            glue("Some male tumors lose ChrY. A male tumor without ChrY and with concordance of ",
                 "{CONCORD_FAIL}% or more has lost Y; with lower concordance it is probably a swap."),
            NA,
            "Marks on the pages", "Box",
            str_c("The background of one type: the box holds the middle half of the values and the line in ",
                  "it is the median; whiskers reach 1.5 times the box width; background outliers are not drawn."),
            "box",
            "Marks on the pages", "Circles",
            "Project samples: red tumor, blue normal, grey tumor/normal pair.", "circles",
            "Marks on the pages", "Ring", "A flagged sample: dark yellow WARN, dark red FAIL.", "rings",
            "Marks on the pages", "Label",
            glue("The name of a flagged sample, up to {N_LABEL} per panel, FAIL first, then by robust z. A ",
                 "pair is labeled with its tumor."),
            "label",
            "Marks on the pages", "Dotted line",
            "A limit on the bad side: dark yellow WARN, dark red FAIL.", "limits",
            "Marks on the pages", "Grey dots", "In the sex plot: the background samples.", "greyDots",
            "Marks on the pages", "Dashed line",
            glue("In the sex plot: ChrY = {SEX_Y_PRESENT}, the cut between male and female."), "dashed"
        )
    ) |>
        mutate(text = as.character(text))
}

#
# Layout: every entry wrapped at fontSize, with its column and its top
# and bottom in inches below the top of the page body
#
glossary_fonts <- function(fontSize) {
    list(
        heading = grid::gpar(fontsize = fontSize + 2, fontface = "bold"),
        term = grid::gpar(fontsize = fontSize, fontface = "bold"),
        text = grid::gpar(fontsize = fontSize, col = "grey15")
    )
}

# Width in inches of each string in the font gp, on the open device
text_width_in <- function(x, gp) {
    map_dbl(x, \(s) grid::convertWidth(grid::grobWidth(grid::textGrob(s, gp = gp)), "in", valueOnly = TRUE))
}

# The lines of an entry wrapped to width inches: the bold term starts the
# first line, two spaces before the text. Returns the text of each line,
# without the term.
wrap_entry <- function(term, text, width, fonts) {
    words <- str_split_1(text, " ")
    space <- text_width_in(" ", fonts$text)
    sizes <- c(text_width_in(term, fonts$term), text_width_in(words, fonts$text))
    line <- fill_bins(sizes, width, c(0, 2 * space, rep(space, len(words) - 1)))[-1]
    map_chr(seq_len(max(line)), \(k) str_c(words[line == k], collapse = " "))
}

glossary_layout <- function(entries, fontSize, dims = GLOSSARY_PORTRAIT) {
    fonts <- glossary_fonts(fontSize)
    lineIn <- fontSize * 1.25 / 72
    headLineIn <- (fontSize + 2) * 1.2 / 72
    headIn <- headLineIn + 0.1
    columnIn <- (dims$width - (dims$columns - 1) * GLOSSARY_GUTTER_IN) / dims$columns
    blocks <- entries |>
        mutate(
            lines = map2(term, text, \(t, x) wrap_entry(t, x, columnIn - GLOSSARY_KEY_IN, fonts)),
            opensSection = section != lag(section, default = ""),
            height = lengths(lines) * lineIn + opensSection * headIn,
            gap = if_else(opensSection, 1.2 * lineIn, 0.4 * lineIn)
        )
    # The lowest column height that holds every entry in the columns
    total <- sum(blocks$height) + sum(blocks$gap[-1])
    columnHeight <- detect(total / dims$columns + seq(0, total, by = 0.01),
                           \(h) max(fill_bins(blocks$height, h, blocks$gap)) <= dims$columns)
    blocks <- blocks |>
        mutate(column = fill_bins(height, columnHeight, gap)) |>
        group_by(column) |>
        mutate(bottom = cumsum(height + if_else(row_number() == 1, 0, gap)), top = bottom - height) |>
        ungroup()
    list(blocks = blocks, fonts = fonts, lineIn = lineIn, headLineIn = headLineIn, headIn = headIn,
         columnIn = columnIn)
}

# The grobs of one entry; top is in inches below the top of its column
glossary_entry_grob <- function(section, term, key, lines, opensSection, top, layout, keys) {
    below <- \(inches) grid::unit(1, "npc") - grid::unit(inches, "in")
    fonts <- layout$fonts
    textTop <- top + opensSection * layout$headIn
    lineY <- below(textTop + (seq_along(lines) - 0.5) * layout$lineIn)
    termIn <- text_width_in(term, fonts$term) + 2 * text_width_in(" ", fonts$text)
    ruleY <- below(top + layout$headLineIn + 0.03)
    grid::gTree(children = grid::gList(
        if (opensSection) {
            grid::textGrob(section, x = 0, y = below(top + layout$headLineIn / 2), hjust = 0, gp = fonts$heading)
        },
        if (opensSection) {
            grid::segmentsGrob(0, ruleY, 1, ruleY, gp = grid::gpar(col = "grey60", lwd = 0.6))
        },
        if (!is.na(key)) {
            # The key's box stops short of the term, so a wide key never touches it
            grid::gTree(children = grid::gList(keys[[key]]),
                        vp = grid::viewport(x = grid::unit((GLOSSARY_KEY_IN - 0.08) / 2, "in"), y = lineY[1],
                                            width = grid::unit(GLOSSARY_KEY_IN - 0.08, "in"),
                                            height = grid::unit(layout$lineIn, "in")))
        },
        grid::textGrob(term, x = grid::unit(GLOSSARY_KEY_IN, "in"), y = lineY[1], hjust = 0, gp = fonts$term),
        grid::textGrob(lines, x = grid::unit(GLOSSARY_KEY_IN + c(termIn, rep(0, len(lines) - 1)), "in"),
                       y = lineY, hjust = 0, gp = fonts$text)
    ))
}

#
# The glossary page, as a function to call with the PDF device open:
# the largest font size from GLOSSARY_FONT down to GLOSSARY_MIN_FONT at
# which the entries fit the page body (dims: GLOSSARY_PORTRAIT or
# GLOSSARY_LANDSCAPE)
#
glossary_page <- function(entries, keys, title, subtitle, dims = GLOSSARY_PORTRAIT) {
    function() {
        fontSize <- detect(seq(GLOSSARY_FONT, GLOSSARY_MIN_FONT, by = -0.5),
                           \(s) max(glossary_layout(entries, s, dims)$blocks$bottom) <= dims$height,
                           .default = GLOSSARY_MIN_FONT)
        layout <- glossary_layout(entries, fontSize, dims)
        columns <- layout$blocks |>
            mutate(grob = pmap(list(section, term, key, lines, opensSection, top),
                               \(...) glossary_entry_grob(..., layout = layout, keys = keys))) %>%
            split(.$column) |>
            map(\(b) grid::gTree(children = rlang::exec(grid::gList, !!!b$grob)))
        nColumns <- len(columns)
        widths <- rep(c(layout$columnIn, GLOSSARY_GUTTER_IN), length.out = 2 * nColumns - 1)
        # A null column takes the rest of the width, so the text sits at the left
        body <- gtable::gtable(widths = grid::unit(c(widths, 1), c(rep("in", len(widths)), "null")),
                               heights = grid::unit(1, "null")) |>
            gtable::gtable_add_grob(columns, t = 1, l = seq(1, by = 2, length.out = nColumns),
                                    clip = "off", name = "glossary-column")
        wrap_elements(full = body) +
            plot_annotation(title = title, subtitle = subtitle, theme = page_theme(9))
    }
}
