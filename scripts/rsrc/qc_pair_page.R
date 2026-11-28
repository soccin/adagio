#
# qc_pair_page.R
#
# One landscape legal page (14 x 8.5 in; QSee's is 17 x 10) per
# tumor/normal pair for qcReport02.R, modeled on Hartwig's QSee report:
#
#   top    the pair, its status and metadata, then the pair's worst FAIL
#   left   a table of QC metrics: the pair's values (tumor red, normal
#          blue, pair-level grey) and, in each row, the QC background of
#          each type as a box with the pair's values as circles. Rows in
#          one block share an x axis.
#   right  QSee's grid of three columns, with QSee's panel shape (about
#          2.2 wide to 1 high): target coverage and insert size (tumor
#          up, normal down; the background's 5th-95th percentile as a
#          band); GC bias and duplicate frequency (tumor and normal on
#          one axis, with the same bands); and, over two rows, the
#          tumor's genes most likely to miss a variant, each over the
#          background tumors' box. Below them, every flagged metric of
#          the pair that is not a table row, drawn as a table row with
#          its own axis (flag_panel), so every flag behind the pair's
#          status is on the page.
#
# After the pair pages: a table of every flag of each pair
# (pair_flag_table), then the legend and glossary. qcReport02.R writes
# it all to Proj_<no>_qcRpt02_samples.pdf.
#
# Flags (rings, shaded cells, the header lines) are the project report's
# (hits in qcReport02.R): the same metrics, limits and types. Rows of
# metrics the project report does not scan have no flags.
#
# Text that is the same on every page (the background, the marks, the
# gene lists) is on the legend and glossary page (qc_pair_glossary.R),
# not on the pair pages.
#
# Design mode (qcReport02.R --design) boxes and names every element of
# the page, for layout work (design_mark).
#
# Needs qc_metric_info.R, qc_plots.R and qc_pair_data.R.
#

PAIR_PAGE_WIDTH <- 14
PAIR_PAGE_HEIGHT <- 8.5
PAIR_MVLH_TOP <- 20
# Widths (in) of the table's text and box columns, and of the plots
PAIR_TABLE_WIDTHS <- c(2, 3)
PAIR_PLOTS_WIDTH <- 8.7
# Panel height (in) of one row of plots; with the panel width (about
# 2.4 in) it sets the panel shape (QSee's panels are 2.96 x 1.36 in).
# Titles and axes add about 1 in to the two rows.
PAIR_PLOT_ROW_IN <- 1.16
PAIR_PLOT_DECOR_IN <- 1
# Rows per page of the flag table after the pair pages
PAIR_TABLE_ROWS <- 30

# Light versions of the ring colors, for flagged value cells
blend_white <- function(col, alpha) {
    m <- grDevices::col2rgb(col)
    grDevices::rgb(t(alpha * m + (1 - alpha) * 255), maxColorValue = 255)
}
CELL_FILLS <- c(WARN = blend_white(LEVEL_COLORS[["WARN"]], 0.3), FAIL = blend_white(LEVEL_COLORS[["FAIL"]], 0.3))
VALUE_COLORS <- c(TN_COLORS, Pair = "grey25")
# Vertical place of each type's box in a table row, and the space (in
# rows) above the first row and below the last of a block, so the rings
# of the outer rows stay inside the block's border
TYPE_OFFSET <- c(Tumor = 0.25, Normal = -0.25, Pair = 0)
ROW_PAD <- 0.25
# Point and ring sizes: small enough that the circles of neighboring
# rows and types do not touch (they are half a row apart)
POINT_SIZE <- 1.25
RING_SIZE <- 2.4
RING_STROKE <- 0.9
# Axis ticks of the table (pt); log axes get long, medium and short
# ticks (QSee's): 10^k, 5 x 10^k, the other multiples
TABLE_TICK_PT <- 2.5
LOG_TICKS <- list(long = 1.4, mid = 0.95, short = 0.55)
# Text positions in the table's value columns (0-1 across the column)
TEXT_X <- c(LABEL = 0.02, Tumor = 0.67, Normal = 0.885, Pair = 0.7775)
TABLE_TEXT_SIZE <- 2.5
# Header fonts (pt): the title, the metadata after it, the flag lines
HEADER_FONTS <- list(
    title = grid::gpar(fontsize = 13, fontface = "bold"),
    meta = grid::gpar(fontsize = 11, col = "grey30"),
    line = grid::gpar(fontsize = 8.5, col = "grey15")
)

#
# Rows of the summary table, top to bottom. AXIS: rows in one block of
# consecutive rows with the same AXIS share an x axis (see pair_axis).
# Tumor and normal values for sample metrics; one value for pair
# metrics (FACETS, Conpair concordance, TMB). No SVs: exomes have almost
# none. TEXT_ROWS show a value but no box.
#
PAIR_ROWS <- tribble(
    ~GROUP,                       ~AXIS,     ~METRIC,                     ~LABEL,
    "Mapping",                    "cov",     "HSM_MEAN_TARGET_COVERAGE",  "Mean coverage",
    "Mapping",                    "depth",   "HSM_PCT_TARGET_BASES_10X",  "Coverage 10x+",
    "Mapping",                    "depth",   "HSM_PCT_TARGET_BASES_20X",  "Coverage 20x+",
    "Mapping",                    "depth",   "HSM_PCT_TARGET_BASES_30X",  "Coverage 30x+",
    "Mapping",                    "depth",   "HSM_PCT_TARGET_BASES_60X",  "Coverage 60x+",
    "Mapping",                    "depth",   "HSM_PCT_TARGET_BASES_100X", "Coverage 100x+",
    "Mapping",                    "depth",   "HSM_PCT_TARGET_BASES_250X", "Coverage 250x+",
    "Mapping",                    "reads",   "ASM_PCT_PF_READS_ALIGNED",  "Reads aligned",
    "Mapping",                    "reads",   "ALFRED_DUPLICATEFRACTION",  "Duplicate reads",
    "Mapping",                    "reads",   "HSM_PCT_EXC_MAPQ",          "Low mapping quality",
    "Mapping",                    "reads",   "HSM_PCT_EXC_BASEQ",         "Low base quality",
    "Copy number (FACETS)",       "frac",    "FACETS_purity",             "Purity",
    "Copy number (FACETS)",       "frac",    "FACETS_frac_loh",           "LOH",
    "Copy number (FACETS)",       "frac",    "FACETS_fga",                "Genome altered (FGA)",
    "Copy number (FACETS)",       "ploidy",  "FACETS_ploidy",             "Ploidy",
    "Copy number (FACETS)",       "count",   "FACETS_n_segs",             "Segments",
    "Copy number (FACETS)",       "count",   "FACETS_N_HOMDEL_GENES",     "Deleted genes",
    "Copy number (FACETS)",       "count",   "FACETS_facets_qc",          "FACETS QC",
    "Contamination and identity", "contam",  "CONPAIR_CONTAMINATION",     "Contamination",
    "Contamination and identity", "concord", "CONPAIR_CONCORDANCE",       "Concordance",
    "Mutational burden",          "rate",    "TEMPO_TMB",                 "TMB (per Mb)"
)
TEXT_ROWS <- "FACETS_facets_qc"
PAIR_LEVEL_PREFIX <- "^(FACETS|TEMPO|MANTA|MAF)_|^CONPAIR_CONCORDANCE$"

#
# Value text for a table cell
#
format_pct <- function(p) {
    v <- 100 * p
    case_when(
        is.na(v) ~ "-",
        v >= 99.995 ~ "100%",
        v >= 99 ~ sprintf("%.2f%%", v),
        v >= 10 ~ sprintf("%.1f%%", v),
        v >= 1 ~ sprintf("%.2f%%", v),
        v == 0 ~ "0%",
        .default = str_c(format(signif(v, 2), scientific = FALSE, drop0trailing = TRUE, trim = TRUE), "%")
    )
}

format_cell <- function(metric, axis, value) {
    case_when(
        is.na(value) ~ "-",
        metric == "FACETS_facets_qc" ~ if_else(value > 0, "pass", "fail"),
        metric == "TEMPO_TMB" ~ sprintf("%.1f", value),
        axis == "cov" ~ sprintf("%.0fx", value),
        axis %in% c("depth", "frac", "reads", "contam") ~ format_pct(value),
        axis == "concord" ~ sprintf("%.2f%%", value),
        axis == "ploidy" ~ sprintf("%.2f", value),
        .default = format(round(value), big.mark = ",", trim = TRUE)
    )
}

#
# Log tick guides, as in QSee: long ticks at powers of 10, medium at 5
# times them, short at the other multiples (ggplot2's
# guide_axis_logticks). Labels only at powers of 10.
#
log_ticks_guide <- function(...) {
    guide_axis_logticks(long = LOG_TICKS$long, mid = LOG_TICKS$mid, short = LOG_TICKS$short, ...)
}

# The same ticks on a log-odds axis (scale_x_log10 of p / (1 - p)),
# mirrored: at p = m x 10^k below 50% and at 1 - p = m x 10^k above it,
# with a medium tick at 50%. Positions in the scale's space; type 1
# long, 2 medium, 3 short.
logit_tick_key <- function(transformation) {
    decades <- 10^(-7:-1)
    low <- tibble(M = rep(1:9, each = len(decades)), P = M * rep(decades, 9)) |>
        filter(P < 0.5) |>
        mutate(TYPE = case_when(M == 1 ~ 1L, M == 5 ~ 2L, .default = 3L))
    ticks <- bind_rows(low, low |> mutate(P = 1 - P), tibble(P = 0.5, TYPE = 2L))
    tibble(X = transformation$transform(ticks$P / (1 - ticks$P)), TYPE = ticks$TYPE)
}

# guide_axis_logticks with the ticks of logit_tick_key: its
# extract_params (ggplot2 4.0) builds params$logkey, the ticks it draws
logit_ticks_guide <- function() {
    ggproto(NULL, log_ticks_guide(),
        extract_params = function(scale, params, ...) {
            aesthetic <- params$aesthetic
            params$name <- str_c(params$name, "_", aesthetic)
            key <- logit_tick_key(scale$get_transformation())
            range <- scale$continuous_range
            key <- key |> filter(X >= range[1], X <= range[2])
            params$logkey <- vctrs::data_frame(!!aesthetic := key$X, .type = key$TYPE, .name_repair = "minimal")
            params
        }
    )
}

#
# x axis of one block of rows: tx (applied to values before plotting),
# scale, and lim (the zoom). values: the background boxes' whisker ends,
# the pair's values and the limits shown.
#
odds_axis <- function(p, breaksP) {
    tx <- \(x) {
        q <- pmin(pmax(x, LOGIT_EPS), 1 - LOGIT_EPS)
        q / (1 - q)
    }
    r <- range(log10(tx(p)))
    pad <- 0.08 * max(diff(r), 0.5)
    list(tx = tx, scale = scale_x_log10(breaks = breaksP / (1 - breaksP), labels = pct_label_each(breaksP),
                                        guide = logit_ticks_guide()),
         lim = 10^(r + c(-pad, pad)))
}

pair_axis <- function(axis, values) {
    v <- values[is.finite(values)]
    if (len(v) == 0) v <- c(0, 1)
    pct <- scales::label_percent(drop0trailing = TRUE)
    switch(axis,
        cov = list(tx = identity, scale = scale_x_continuous(labels = scales::label_number(suffix = "x")),
                   lim = c(0, max(v) * 1.05)),
        depth = ,
        frac = list(tx = identity, scale = scale_x_continuous(labels = pct, breaks = seq(0, 1, 0.25)),
                    lim = c(0, 1)),
        reads = odds_axis(v, c(1e-5, 1e-4, 1e-3, 0.01, 0.1, 0.9, 0.99, 0.999, 0.9999)),
        concord = odds_axis(v / 100, c(0.9, 0.99, 0.999, 0.9999)) |>
            (\(a) list(tx = \(x) a$tx(x / 100), scale = a$scale, lim = a$lim))(),
        ploidy = list(tx = identity, scale = scale_x_continuous(), lim = range(c(1.5, 4.5, v))),
        contam = list(tx = \(x) pmax(x, 1e-4),
                      scale = scale_x_log10(breaks = 10^(-5:0), labels = pct, guide = log_ticks_guide()),
                      lim = c(1e-4, max(0.07, max(v) * 1.3))),
        count = list(tx = identity,
                     scale = scale_x_continuous(transform = scales::pseudo_log_trans(base = 10),
                                                breaks = c(0, 10^(0:5)),
                                                labels = scales::label_number(big.mark = ","),
                                                guide = log_ticks_guide(negative.small = 1)),
                     lim = c(0, max(1, max(v)) * 1.3)),
        # Rates (TMB per Mb): a log axis; values below 0.1 are drawn at 0.1
        rate = list(tx = \(x) pmax(x, 0.1),
                    scale = scale_x_log10(breaks = 10^(-1:4), labels = scales::label_number(drop0trailing = TRUE),
                                          guide = log_ticks_guide()),
                    lim = c(max(0.1, min(v) / 1.5), max(1, max(v)) * 1.5)),
        stop(glue("Unknown axis {axis}"))
    )
}

#
# One block: the text cells (left) and the boxes (right) of rows that
# share an axis. boxes: background_boxes() of the rows' metrics. vals:
# METRIC, TYPE, VALUE, LEVEL. lims: METRIC, TYPE, LEVEL, LIMIT. title:
# the group name, or NULL.
#
block_rows <- function(rows) rows |> mutate(ROW_Y = rev(seq_len(n())))

place_rows <- function(df, rows) {
    df |>
        inner_join(rows |> select(METRIC, ROW_Y), by = "METRIC") |>
        mutate(Y = ROW_Y + TYPE_OFFSET[TYPE])
}

# vals may carry the cell text (TEXT); else format_cell gives it.
# textX: text positions as TEXT_X; cellW: width of a sample's shaded
# cell (0-1 across the column)
text_block <- function(rows, vals, title, textX = TEXT_X, cellW = 0.2) {
    rows <- block_rows(rows)
    n <- nrow(rows)
    hasText <- "TEXT" %in% names(vals)
    cells <- vals |>
        inner_join(rows |> select(METRIC, ROW_Y, AXIS), by = "METRIC") |>
        mutate(
            X = textX[TYPE],
            W = if_else(TYPE == "Pair", 0.42, cellW),
            TEXT = if (hasText) TEXT else format_cell(METRIC, AXIS, VALUE)
        )
    ggplot() +
        geom_hline(yintercept = seq_len(n - 1) + 0.5, colour = "grey90", linewidth = 0.3) +
        geom_tile(data = cells |> filter(!is.na(LEVEL)), aes(x = X, y = ROW_Y, width = W, fill = LEVEL),
                  height = 0.86) +
        geom_text(data = rows, aes(x = textX[["LABEL"]], y = ROW_Y, label = LABEL), hjust = 0,
                  size = TABLE_TEXT_SIZE) +
        geom_text(data = cells, aes(x = X, y = ROW_Y, label = TEXT, colour = TYPE), size = TABLE_TEXT_SIZE) +
        scale_fill_manual(values = CELL_FILLS, guide = "none") +
        scale_colour_manual(values = VALUE_COLORS, guide = "none") +
        scale_x_continuous(limits = c(0, 1), expand = expansion(0)) +
        scale_y_continuous(limits = c(0.5 - ROW_PAD, n + 0.5 + ROW_PAD), expand = expansion(0)) +
        labs(title = title) +
        theme_void(base_size = 8) +
        theme(plot.title = element_text(size = 8.5, face = "bold", margin = margin(b = 2)))
}

# axisFn: the axis (tx, scale, lim) for the values it must show; by
# default the block's AXIS (pair_axis)
box_block <- function(rows, boxes, vals, lims, axisFn = \(v) pair_axis(rows$AXIS[1], v)) {
    rows <- block_rows(rows)
    n <- nrow(rows)
    plotRows <- rows |> filter(!METRIC %in% TEXT_ROWS)
    boxes <- boxes |> place_rows(plotRows)
    vals <- vals |> filter(is.finite(VALUE)) |> place_rows(plotRows)
    lims <- lims |> place_rows(plotRows)
    ax <- axisFn(c(boxes$WMIN, boxes$WMAX, vals$VALUE, lims$LIMIT))
    boxes <- boxes |> mutate(across(c(LOWER, MIDDLE, UPPER, WMIN, WMAX), ax$tx))
    vals <- vals |> mutate(X = ax$tx(VALUE))
    lims <- lims |> mutate(X = ax$tx(LIMIT), LINE = LEVEL_COLORS[LEVEL])
    flagged <- vals |>
        filter(!is.na(LEVEL)) |>
        mutate(RING = LEVEL_COLORS[LEVEL])
    tick <- aes(x = X, xend = X, y = Y - 0.15, yend = Y + 0.15)

    ggplot(mapping = aes(x = X, y = Y)) +
        geom_hline(yintercept = seq_len(n - 1) + 0.5, colour = "grey90", linewidth = 0.3) +
        geom_segment(data = lims, tick, colour = LIMIT_BASE_COLOR, linewidth = 0.6) +
        geom_segment(data = lims, aes(x = X, xend = X, y = Y - 0.15, yend = Y + 0.15, colour = LINE),
                     linetype = "11", linewidth = 0.6) +
        geom_boxplot(data = boxes, box_aes(), stat = "identity", inherit.aes = FALSE, orientation = "y",
                     width = 0.28, alpha = 0.3, colour = "grey65", linewidth = 0.3) +
        geom_point(data = vals, aes(fill = TYPE), shape = 21, colour = "black", stroke = 0.4, size = POINT_SIZE) +
        geom_point(data = flagged, aes(colour = RING), shape = 21, fill = NA, size = RING_SIZE, stroke = RING_STROKE) +
        scale_fill_manual(values = TYPE_COLORS, guide = "none") +
        scale_colour_identity() +
        scale_y_continuous(limits = c(0.5 - ROW_PAD, n + 0.5 + ROW_PAD), expand = expansion(0), breaks = NULL) +
        ax$scale +
        coord_cartesian(xlim = ax$lim) +
        labs(x = NULL, y = NULL) +
        qc_theme(7, 8) +
        theme(
            panel.grid.major.y = element_blank(),
            axis.text.x = element_text(size = 6),
            axis.ticks.length.x = unit(TABLE_TICK_PT, "pt"),
            plot.margin = margin(0, 4, 2, 2)
        )
}

# Column heads over the values; nothing over the boxes
table_header <- function() {
    heads <- tibble(X = TEXT_X[c("Tumor", "Normal")], LABEL = c("Tumor", "Normal"), TYPE = c("Tumor", "Normal"))
    text <- ggplot(heads, aes(X, 0.5, label = LABEL, colour = TYPE)) +
        geom_text(size = 2.8, fontface = "bold") +
        scale_colour_manual(values = VALUE_COLORS, guide = "none") +
        scale_x_continuous(limits = c(0, 1), expand = expansion(0)) +
        scale_y_continuous(limits = c(0, 1), expand = expansion(0)) +
        theme_void()
    list(text, plot_spacer())
}

#
# Design mode (qcReport02.R --design), for layout work: every element of
# the page gets a purple box and an ID in its top right corner. H the
# header; T0, T1, ... the table's text column and B0, B1, ... its box
# column (0 the column heads, then one per block); P1, P2, ... the cells
# of the plot grid, by rows, empty cells included; FT1, FB1, ... the text
# and box cells of the flagged metrics below the plots. The marks do not move
# anything: the ID is drawn over the element, and the elements that
# stand in for a spacer or an empty cell have the same margins.
#
DESIGN_COLOR <- "purple"

design_mark <- function(x, id, position = "topright") {
    # patchwork draws only the background of a spacer, not its tag
    if (inherits(x, "spacer")) x <- wrap_elements(full = grid::nullGrob())
    x + labs(tag = id) + theme(
        plot.background = element_rect(colour = DESIGN_COLOR, fill = NA, linewidth = 1),
        plot.tag = element_text(colour = DESIGN_COLOR, face = "bold", size = 9, margin = margin(2, 3, 2, 3)),
        plot.tag.position = position,
        plot.tag.location = "plot"
    )
}

# The plot grid with each empty cell (#) its own element, as patchwork
# fills it (no margins), and every cell marked P1, P2, ... by rows.
# cells: named list of the grid's plots; layout: patchwork design.
design_grid <- function(cells, layout) {
    chars <- str_split_1(layout, "")
    holes <- which(chars == "#")
    chars[holes] <- setdiff(LETTERS, chars)[seq_along(holes)]
    order <- unique(str_subset(chars, "^[A-Z]$"))
    empty <- setdiff(order, names(cells))
    cells <- c(cells, map(set_names(empty), \(l) wrap_elements(full = grid::nullGrob()) +
                                                theme(plot.margin = margin(0))))
    list(cells = map2(cells[order], str_c("P", seq_along(order)), design_mark),
         layout = str_c(chars, collapse = ""))
}

# The whole table: a header row, then one text and one box plot per
# block, aligned by patchwork. boxes: background_boxes() of the rows
pair_table <- function(boxes, vals, lims, design = FALSE) {
    blocks <- PAIR_ROWS |>
        mutate(BLOCK = consolidate_blocks(GROUP, AXIS), FIRST_IN_GROUP = !duplicated(GROUP))
    plots <- blocks |>
        group_split(BLOCK) |>
        map(\(rows) list(
            text_block(rows, vals |> filter(METRIC %in% rows$METRIC), if (rows$FIRST_IN_GROUP[1]) rows$GROUP[1]),
            box_block(rows, boxes |> filter(METRIC %in% rows$METRIC), vals |> filter(METRIC %in% rows$METRIC),
                      lims |> filter(METRIC %in% rows$METRIC))
        )) |>
        list_flatten()
    heights <- c(0.5, blocks |> count(BLOCK) |> pull(n) + 2 * ROW_PAD)
    cells <- c(table_header(), plots)
    if (design) {
        cells <- map2(cells, str_c(rep(c("T", "B"), len(heights)), rep(seq_along(heights) - 1, each = 2)), design_mark)
    }
    wrap_plots(cells, ncol = 2, widths = PAIR_TABLE_WIDTHS, heights = heights)
}

# Block number of each row: a new block where the group or axis changes
consolidate_blocks <- function(group, axis) {
    key <- str_c(group, "|", axis)
    cumsum(key != lag(key, default = ""))
}

#
# Flagged metrics not in the table, below the plots: every scanned
# metric with a FAIL or WARN in this pair that is not a table row, worst
# first, each drawn as a table row with its own axis. FLAG_SLOTS rows at
# most (the rest are in the flag table after the pair pages); unused
# slots are blank, so a row is as tall as a table row whatever the count.
#
FLAG_SLOTS <- 10
# A wider text column than the table's, with the values further right:
# metric names run to about 40 characters
FLAG_WIDTHS <- c(3.4, PAIR_PLOTS_WIDTH - 3.4)
FLAG_TEXT_X <- c(LABEL = 0.02, Tumor = 0.76, Normal = 0.92, Pair = 0.84)
FLAG_CELL_W <- 0.15
FLAG_TITLE <- "Flagged metrics not in the table"
ODDS_BREAKS <- c(1e-5, 1e-4, 1e-3, 0.01, 0.1, 0.5, 0.9, 0.99, 0.999, 0.9999)

# Cell text by the metric's kind (metric_info): percentages to 3
# significant digits, read counts as 175.7M, coverage as 74x, other
# numbers to 4 (as the flag table)
flag_text <- function(value, kind, scaleBy) {
    kind <- rep(kind, len(value))
    scaleBy <- rep(scaleBy, len(value))
    case_when(
        is.na(value) ~ "-",
        kind %in% PERCENT_KINDS ~ format_value(value, kind, scaleBy),
        kind == "count" ~ scales::label_number(accuracy = 0.1, scale_cut = scales::cut_short_scale())(value),
        kind == "cov" ~ sprintf("%.0fx", value),
        kind == "bp" ~ sprintf("%.0f bp", value),
        .default = format_num(value)
    )
}

#
# The axis of one flagged metric: the type the summary report's panel
# for the metric has (axis_spec in qc_plots.R), with the table's ticks:
# log axes labeled at powers of 10 only, log-odds axes at ODDS_BREAKS. A
# log-odds axis over values that all lie between 5% and 95% is linear.
# infoRow: the metric's row of metric_info(); dataValues: all its
# background and pair values; rangeValues: what the axis must show.
#
flag_axis <- function(infoRow, bg, dataValues, rangeValues) {
    ax <- axis_spec(infoRow, bg, dataValues, rangeValues)
    scaleBy <- infoRow$SCALE_BY
    r <- rangeValues[is.finite(rangeValues)]
    p <- r / scaleBy
    if (ax$type == "logodds" && all(p > 0.05 & p < 0.95)) {
        return(list(tx = \(x) x / scaleBy, scale = scale_x_continuous(labels = scales::label_percent()),
                    lim = frac_range(p)))
    }
    switch(ax$type,
        logodds = {
            a <- odds_axis(p, ODDS_BREAKS)
            list(tx = \(x) a$tx(x / scaleBy), scale = a$scale, lim = a$lim)
        },
        log = {
            x <- ax$tx(r)
            decades <- log10(range(x[x > 0]))
            k <- floor(decades[1]):ceiling(decades[2])
            list(tx = ax$tx,
                 scale = scale_x_log10(breaks = 10^k, labels = ax$scale$labels, guide = log_ticks_guide()),
                 lim = 10^range(k))
        },
        {
            x <- ax$tx(r)
            list(tx = ax$tx, scale = ax$scale, lim = ax$xlim %||% (range(x) + c(-1, 1) * 0.05 * diff(range(x))))
        }
    )
}

# An unused slot: a blank text cell (with the title in the first slot)
# and a box cell with an invisible axis as tall as a real one
blank_flag_slot <- function(title = NULL) {
    text <- ggplot() +
        labs(title = title) +
        theme_void(base_size = 8) +
        theme(plot.title = element_text(size = 8.5, face = "bold", margin = margin(b = 2)))
    box <- ggplot() +
        scale_x_continuous(limits = c(0, 1), breaks = 0.5, labels = "0") +
        qc_theme(7, 8) +
        theme(
            panel.border = element_blank(),
            panel.grid = element_blank(),
            axis.text.x = element_text(size = 6, colour = NA),
            axis.ticks.x = element_line(colour = NA),
            axis.ticks.length.x = unit(TABLE_TICK_PT, "pt"),
            plot.margin = margin(0, 4, 2, 2)
        )
    list(text, box)
}

#
# The block below the plots. metrics: the flagged metrics not in the
# table, worst first. bg: TYPE, METRIC, VALUE; boxes: background_boxes()
# of bg; vals: SAMPLE, TYPE, METRIC, VALUE, LEVEL of the pair; lims: as
# for the table; info: metric_info(). One element (wrap_elements), so
# the page grid treats it as one cell.
#
flag_panel <- function(metrics, bg, boxes, vals, lims, info, design = FALSE) {
    shown <- head(metrics, FLAG_SLOTS)
    title <- case_when(
        len(metrics) == 0 ~ str_c(FLAG_TITLE, ": none"),
        len(metrics) > FLAG_SLOTS ~ str_c(FLAG_TITLE, glue(" (the {FLAG_SLOTS} worst of {len(metrics)})")),
        .default = FLAG_TITLE
    )
    cells <- shown |>
        imap(\(m, i) {
            infoRow <- info |> filter(METRIC == m) |> slice_head(n = 1)
            rows <- tibble(GROUP = FLAG_TITLE, AXIS = "flag", METRIC = m, LABEL = infoRow$LABEL)
            v <- vals |>
                filter(METRIC == m) |>
                mutate(TEXT = flag_text(VALUE, infoRow$KIND, infoRow$SCALE_BY))
            b <- bg |> filter(METRIC == m)
            list(
                text_block(rows, v, if (i == 1) title, FLAG_TEXT_X, FLAG_CELL_W),
                box_block(rows, boxes |> filter(METRIC == m), v, lims |> filter(METRIC == m),
                          axisFn = \(r) flag_axis(infoRow, b, c(b$VALUE, v$VALUE), r))
            )
        }) |>
        list_flatten()
    blanks <- seq_len(FLAG_SLOTS - len(shown)) |>
        map(\(i) blank_flag_slot(if (len(shown) == 0 && i == 1) title)) |>
        list_flatten()
    cells <- c(cells, blanks)
    # In design mode the row IDs go bottom right; the block's own ID (P6)
    # is top right
    if (design) {
        cells <- map2(cells, str_c(rep(c("FT", "FB"), FLAG_SLOTS), rep(seq_len(FLAG_SLOTS), each = 2)),
                      \(x, id) design_mark(x, id, "bottomright"))
    }
    wrap_elements(full = wrap_plots(cells, ncol = 2, widths = FLAG_WIDTHS,
                                    heights = rep(1 + 2 * ROW_PAD, FLAG_SLOTS)))
}

#
# Distributions binned for the plots: per sample, the fraction of the
# total in each bin of width binWidth (BIN: bin middle), up to xmax
#
bin_fractions <- function(df, x, count, binWidth, xmax) {
    df |>
        rename(X = all_of(x), N = all_of(count)) |>
        mutate(TOTAL = sum(N), .by = SAMPLE) |>
        filter(X <= xmax) |>
        mutate(BIN = floor(X / binWidth) * binWidth + binWidth / 2) |>
        summarize(FRAC = sum(N) / first(TOTAL), .by = c(SAMPLE, BIN)) |>
        complete(SAMPLE, BIN = seq(binWidth / 2, xmax, by = binWidth), fill = list(FRAC = 0))
}

# Background band per type and bin: 5th and 95th percentile, median of
# the column value
background_band <- function(binned, sampleTypes, value = "FRAC") {
    binned |>
        inner_join(sampleTypes, by = "SAMPLE") |>
        summarize(
            LO = quantile(.data[[value]], 0.05, names = FALSE),
            MED = median(.data[[value]]),
            HI = quantile(.data[[value]], 0.95, names = FALSE),
            .by = c(TYPE, BIN)
        )
}

# GC-bias curves (dist$target_gc_bias) as BIN (GC bin middle), Y (median
# coverage / the sample's median target coverage)
gc_bias_bins <- function(curves) {
    curves |> transmute(SAMPLE, BIN = GC_BIN, Y = MEDIAN_NORM_COV)
}

# fastp duplicate histograms (dist$fastp_dup_hist), lanes summed: per
# sample, the fraction Y of the fragments fastp samples (about one per
# 12-base key) seen BIN times; BIN 31 is 31 or more
dup_fractions <- function(hist) {
    hist |>
        summarize(N = sum(N_SETS), .by = c(SAMPLE, DUP_LEVEL)) |>
        mutate(Y = N / sum(N), .by = SAMPLE) |>
        transmute(SAMPLE, BIN = DUP_LEVEL, Y)
}

# The value below which a fraction q of each sample's total lies; the
# x range of a distribution plot covers it for every sample
upper_quantile <- function(df, x, count, q = 0.99) {
    df |>
        rename(X = all_of(x), N = all_of(count)) |>
        arrange(SAMPLE, X) |>
        summarize(XQ = X[which(cumsum(N) / sum(N) >= q)[1]], .by = SAMPLE) |>
        pull(XQ)
}

#
# A distribution plot: the tumor above the zero line, the normal below;
# the background band of each type, the pair's lines, and a vertical
# line at each sample's median (medians: TYPE, X, FRAC)
#
mirror_plot <- function(proj, band, medians, title, xlab, ylab, xmax) {
    side <- c(Tumor = 1, Normal = -1)
    proj <- proj |> mutate(Y = side[TYPE] * FRAC)
    band <- band |> mutate(YLO = side[TYPE] * LO, YHI = side[TYPE] * HI)
    medians <- medians |> mutate(Y = side[TYPE] * FRAC)
    ggplot() +
        geom_ribbon(data = band, aes(x = BIN, ymin = YLO, ymax = YHI, fill = TYPE), alpha = 0.22) +
        geom_hline(yintercept = 0, colour = "grey50", linewidth = 0.3) +
        geom_segment(data = medians, aes(x = X, xend = X, y = 0, yend = Y, colour = TYPE), linewidth = 0.4) +
        geom_line(data = proj, aes(x = BIN, y = Y, colour = TYPE), linewidth = 0.6) +
        scale_fill_manual(values = TN_COLORS, guide = "none") +
        scale_colour_manual(values = TN_COLORS, guide = "none") +
        scale_y_continuous(labels = \(y) scales::label_percent(drop0trailing = TRUE)(abs(y))) +
        scale_x_continuous(expand = expansion(mult = c(0, 0.01))) +
        coord_cartesian(xlim = c(0, xmax)) +
        labs(title = title, x = xlab, y = ylab) +
        qc_theme(8, 9) +
        theme(panel.grid.major.y = element_blank(), plot.margin = margin(4, 6, 4, 4))
}

# A panel with no plot: the title, "Not computed" and why (subtitle)
not_computed_plot <- function(title, subtitle) {
    ggplot() +
        annotate("text", x = 0, y = 0, label = "Not computed", size = 3) +
        labs(title = title, subtitle = subtitle) +
        theme_void(base_size = 8) +
        theme(plot.title = element_text(face = "bold", size = 9),
              plot.subtitle = element_text(size = 6.8, colour = "grey30"))
}

#
# A per-bin plot with the tumor and the normal on one axis: the
# background band of each type, a reference line (refY, or none) and the
# pair's lines, with a point per bin when points is TRUE. proj: TYPE,
# BIN, Y; band: TYPE, BIN, LO, HI. Interior missing values break a line.
#
overlay_plot <- function(proj, band, title, xlab, ylab, subtitle = NULL, refY = NULL, points = FALSE) {
    ggplot(mapping = aes(x = BIN)) +
        geom_ribbon(data = band, aes(ymin = LO, ymax = HI, fill = TYPE), alpha = 0.22) +
        (if (!is.null(refY)) geom_hline(yintercept = refY, colour = "grey50", linewidth = 0.3)) +
        geom_line(data = proj, aes(y = Y, colour = TYPE), linewidth = 0.6, na.rm = TRUE) +
        (if (points) geom_point(data = proj, aes(y = Y, colour = TYPE), size = 0.6, na.rm = TRUE)) +
        scale_fill_manual(values = TN_COLORS, guide = "none") +
        scale_colour_manual(values = TN_COLORS, guide = "none") +
        labs(title = title, subtitle = subtitle, x = xlab, y = ylab) +
        qc_theme(8, 9) +
        theme(panel.grid.major.y = element_blank(), plot.subtitle = element_text(size = 6.8, colour = "grey30"),
              plot.margin = margin(4, 6, 4, 4))
}

#
# GC bias, the exome version of QSee's COBALT plot: each sample's median
# target coverage per 1% bin of target GC, over its median target
# coverage (dist$target_gc_bias)
#
gc_bias_plot <- function(proj, band, subtitle = NULL) {
    if (nrow(proj) == 0) return(not_computed_plot("GC bias", subtitle))
    overlay_plot(proj, band, "GC bias", "Target GC", "Coverage / median", subtitle, refY = 1) +
        scale_x_continuous(labels = scales::label_percent(), expand = expansion(0))
}

#
# Duplicate frequency (fastp): the percent of fragments seen 1, 2, ...
# 31 or more times, on a log axis. Zeros are off the axis: a line breaks
# there, and a band that reaches 0 runs off the bottom.
#
DUP_FLOOR <- 1e-7

dup_freq_plot <- function(proj, band, subtitle = NULL) {
    if (nrow(proj) == 0) return(not_computed_plot("Duplicate frequency", subtitle))
    proj <- proj |> mutate(Y = if_else(Y > 0, Y, NA_real_))
    band <- band |> mutate(across(c(LO, HI), \(y) pmax(y, DUP_FLOOR / 10)))
    yBreaks <- 10^seq(-6, 0, 2)
    overlay_plot(proj, band, "Duplicate frequency", "Read pairs per fragment", "Fragments", subtitle,
                 points = TRUE) +
        scale_x_continuous(breaks = c(1, 5, 10, 15, 20, 25, 31), labels = c(1, 5, 10, 15, 20, 25, "31+"),
                           expand = expansion(mult = 0.02)) +
        scale_y_log10(breaks = yBreaks, labels = pct_label_each(yBreaks), guide = log_ticks_guide()) +
        coord_cartesian(ylim = c(DUP_FLOOR, 1))
}

#
# Missed-variant likelihood: the PAIR_MVLH_TOP genes with the highest
# value, as points over the gene's box in the background tumors (bg:
# SAMPLE, GENE, MVLH); on stems when there is no background. Genes in
# drivers get a "*"; genes with coding bases outside the targets (not
# counted) get a "#".
#
MVLH_PART_IN_TARGETS <- 0.95
MVLH_AXIS_MIN <- 0.05

mvlh_plot <- function(m, bg, type, drivers, title, subtitle) {
    if (is.null(m) || nrow(m) == 0) return(not_computed_plot(title, subtitle))
    top <- m |>
        slice_max(MVLH, n = PAIR_MVLH_TOP, with_ties = FALSE) |>
        mutate(
            GENE_LABEL = str_c(GENE, if_else(GENE %in% drivers, " *", ""),
                               if_else(FRAC_IN_TARGETS < MVLH_PART_IN_TARGETS, " #", "")),
            GENE_LABEL = fct_reorder(GENE_LABEL, MVLH)
        )
    bgTop <- bg |>
        inner_join(top |> select(GENE, GENE_LABEL), by = "GENE")
    # The axis covers the boxes' whiskers (1.5 IQR past the box, at most
    # the largest value); the zoom does not change the boxes
    whiskers <- bgTop |>
        summarize(Q1 = quantile(MVLH, 0.25, names = FALSE), Q3 = quantile(MVLH, 0.75, names = FALSE),
                  HI = min(max(MVLH), Q3 + 1.5 * (Q3 - Q1)), .by = GENE) |>
        pull(HI)
    xmax <- max(MVLH_AXIS_MIN, max(c(top$MVLH, whiskers)) * 1.12)
    ggplot(top, aes(x = MVLH, y = GENE_LABEL)) +
        (if (nrow(bgTop) == 0) {
            geom_segment(aes(x = 0, xend = MVLH, yend = GENE_LABEL), colour = "grey75", linewidth = 0.4)
        } else {
            geom_boxplot(data = bgTop, aes(group = GENE_LABEL), orientation = "y", width = 0.6,
                         fill = TYPE_COLORS[[type]], alpha = 0.3, colour = "grey65", linewidth = 0.3,
                         outliers = FALSE)
        }) +
        geom_point(shape = 21, fill = TN_COLORS[[type]], colour = "black", stroke = 0.4, size = 1.7) +
        scale_x_continuous(labels = scales::label_percent(drop0trailing = TRUE), expand = expansion(c(0, 0.02))) +
        coord_cartesian(xlim = c(0, xmax)) +
        labs(title = title, subtitle = subtitle, x = "Missed-variant likelihood", y = NULL) +
        qc_theme(8, 9) +
        theme(
            axis.text.y = element_text(size = 6.2),
            axis.ticks.y = element_blank(),
            plot.subtitle = element_text(size = 6.8, colour = "grey30"),
            plot.margin = margin(4, 6, 4, 4)
        )
}

#
# The pair's status, and its worst flag for the header: the first flag
# in the project report's order (FAIL first, then by robust z), by name
# only, e.g. "Worst FAIL: tumor Total Reads in BAM", or "Worst WARN: ..."
# when the pair has no FAIL. Every flag is drawn on the page, in the
# table or below the plots. hits: the project report's flagged rows of
# this pair, in its order; labels: METRIC, LABEL.
#
pair_status <- function(hits) {
    if (any(hits$LEVEL == "FAIL")) "FAIL" else if (nrow(hits) > 0) "WARN" else "PASS"
}

worst_flag_line <- function(hits, labels) {
    worst <- hits |>
        slice_head(n = 1) |>
        left_join(labels |> select(METRIC, METRIC_LABEL = LABEL), by = "METRIC")
    if (nrow(worst) == 0) return(character())
    glue("Worst {worst$LEVEL}: {str_to_lower(worst$TYPE)} {worst$METRIC_LABEL}")
}

# The pair's metadata for the title line: patient, tumor OncoTree code,
# preservation and origin of each sample, and the sex called from the
# normal, with the sex check's problems when it finds any (qc_sex.R)
pair_meta_text <- function(tMeta, nMeta, sexRow) {
    describe <- \(type, m) {
        if (nrow(m) == 0) return(NULL)
        d <- str_c(na.omit(c(m$preservation, m$sampleOrigin)), collapse = " ")
        if (d != "") glue("{type} {d}")
    }
    sexText <- if (nrow(sexRow) == 1) {
        if (sexRow$STATUS == "OK") sexRow$CALL else glue("{sexRow$CALL}; sex check: {sexRow$STATUS}")
    }
    str_c(
        c(
            if (nrow(tMeta) > 0 && !is.na(tMeta$cmoPatientId)) glue("Patient {tMeta$cmoPatientId}"),
            if (nrow(tMeta) > 0 && !is.na(tMeta$oncoTreeCode)) tMeta$oncoTreeCode,
            describe("tumor", tMeta),
            describe("normal", nMeta),
            sexText
        ),
        collapse = "; "
    )
}

#
# The page header: the title in bold with the metadata after it on the
# same baseline, then the lines (none or more). Returns the grob and its
# height in inches.
#
pair_header <- function(title, meta, lines) {
    titleIn <- HEADER_FONTS$title$fontsize * 1.3 / 72
    lineIn <- HEADER_FONTS$line$fontsize * 1.3 / 72
    below <- \(inches) grid::unit(1, "npc") - grid::unit(inches, "in")
    baseline <- below(0.8 * titleIn)
    titleWidth <- grid::grobWidth(grid::textGrob(title, gp = HEADER_FONTS$title))
    grob <- grid::gTree(children = grid::gList(
        grid::textGrob(title, x = 0, y = baseline, hjust = 0, vjust = 0, gp = HEADER_FONTS$title),
        grid::textGrob(meta, x = titleWidth + grid::unit(0.3, "in"), y = baseline, hjust = 0, vjust = 0,
                       gp = HEADER_FONTS$meta),
        if (len(lines) > 0) {
            grid::textGrob(lines, x = 0, y = below(titleIn + (seq_along(lines) - 0.4) * lineIn), hjust = 0,
                           gp = HEADER_FONTS$line)
        }
    ))
    list(grob = grob, height = titleIn + len(lines) * lineIn)
}

#
# The page of one pair. ctx holds what every page shares (see
# pair_report_pages); p is the pair's row of the pairing.
#
pair_page <- function(p, ctx) {
    ids <- c(p$TUMOR_ID, p$NORMAL_ID, p$PAIR)
    vals <- ctx$vals |> filter(SAMPLE %in% ids)
    hits <- ctx$hits |> filter(SAMPLE %in% ids)
    status <- pair_status(hits)

    table <- pair_table(ctx$boxes, vals, ctx$lims, ctx$design)

    sampleType <- tibble(SAMPLE = c(p$TUMOR_ID, p$NORMAL_ID), TYPE = c("Tumor", "Normal"))
    covProj <- ctx$covBinned |> inner_join(sampleType, by = "SAMPLE")
    insProj <- ctx$insBinned |> inner_join(sampleType, by = "SAMPLE")
    at_median <- \(binned, metric, width) vals |>
        filter(METRIC == metric, TYPE %in% c("Tumor", "Normal")) |>
        transmute(SAMPLE, TYPE, X = VALUE, BIN = floor(VALUE / width) * width + width / 2) |>
        left_join(binned |> select(SAMPLE, BIN, FRAC), by = c("SAMPLE", "BIN")) |>
        filter(is.finite(X), !is.na(FRAC))
    covPlot <- mirror_plot(covProj, ctx$covBand, at_median(ctx$covBinned, "HSM_MEDIAN_TARGET_COVERAGE", ctx$covBin),
                           "Target coverage", "Coverage (x)", "Target bases", ctx$covMax)
    insPlot <- mirror_plot(insProj, ctx$insBand, at_median(ctx$insBinned, "ALFRED_MEDIANINSERTSIZE", ctx$insBin),
                           "Insert size", "Insert size (bp)", "Read pairs", ctx$insMax)
    gcPlot <- gc_bias_plot(ctx$gcProj |> inner_join(sampleType, by = "SAMPLE"), ctx$gcBand, ctx$notes$gc)
    dupPlot <- dup_freq_plot(ctx$dupProj |> inner_join(sampleType, by = "SAMPLE"), ctx$dupBand, ctx$notes$dup)

    # Missed-variant likelihood in the tumor. The plot has a subtitle
    # only when something is missing: this pair's OncoTree code, IntOGen
    # drivers for it or purity, or the QC background
    tMeta <- ctx$sampleMeta |> filter(SAMPLE == p$TUMOR_ID)
    nMeta <- ctx$sampleMeta |> filter(SAMPLE == p$NORMAL_ID)
    oncotree <- (tMeta$oncoTreeCode %||% NA_character_)[1]
    family <- oncotree_family(oncotree, ctx$genes$oncotree)
    drivers <- ctx$genes$intogen |> filter(CANCER_TYPE %in% family) |> pull(GENE) |> unique()
    purity <- vals |> filter(METRIC == "FACETS_purity") |> pull(VALUE)
    tNote <- c(
        if (!(len(purity) == 1 && is.finite(purity))) "No FACETS purity",
        if (is.na(oncotree)) "No OncoTree code: no * marks" else
            if (len(drivers) == 0) glue("No IntOGen drivers for {oncotree}: no * marks"),
        ctx$notes$mvlh
    )
    mvlhPlot <- mvlh_plot(ctx$mvlh |> filter(SAMPLE == p$TUMOR_ID), ctx$bgMvlh, "Tumor", drivers,
                          "Genes most likely to miss a variant",
                          if (len(tNote) > 0) str_c(tNote, collapse = "; "))

    header <- pair_header(
        glue("{p$TUMOR_ID} / {p$NORMAL_ID}: {status}"),
        pair_meta_text(tMeta, nMeta, ctx$sexTbl |> filter(PAIR == p$PAIR)),
        worst_flag_line(hits, ctx$labels)
    )

    # Flags of metrics that are not table rows, below the plots
    flagPanel <- flag_panel(
        hits |> filter(!METRIC %in% PAIR_ROWS$METRIC) |> distinct(METRIC) |> pull(METRIC),
        ctx$flagBg, ctx$flagBoxes, ctx$flagVals |> filter(SAMPLE %in% ids), ctx$flagLims, ctx$info, ctx$design
    )

    # QSee's grid: coverage and insert size in the first row, GC bias and
    # duplicate frequency in the second, the genes over both rows in the
    # third column; the flagged metrics not in the table below. Heights
    # are relative panel heights (inch units do not mix with the nested
    # table), so the last row gets the rest of the body's height
    bodyIn <- PAIR_PAGE_HEIGHT - header$height - 0.25
    plotGrid <- list(cells = list(A = covPlot, B = insPlot, C = mvlhPlot, D = gcPlot, E = dupPlot,
                                  F = flagPanel),
                     layout = "ABC\nDEC\nFFF")
    top <- wrap_elements(full = header$grob)
    if (ctx$design) {
        plotGrid <- design_grid(plotGrid$cells, plotGrid$layout)
        top <- design_mark(top, "H")
    }
    right <- wrap_plots(plotGrid$cells, design = plotGrid$layout,
                        heights = c(PAIR_PLOT_ROW_IN, PAIR_PLOT_ROW_IN,
                                    bodyIn - PAIR_PLOT_DECOR_IN - 2 * PAIR_PLOT_ROW_IN))
    body <- wrap_plots(table, right, widths = c(sum(PAIR_TABLE_WIDTHS), PAIR_PLOTS_WIDTH))
    wrap_plots(top, body, ncol = 1, heights = grid::unit(c(header$height, 1), c("in", "null")))
}

#
# Every flag of each pair, in page order, for the table after the pair
# pages: FAIL first, then by robust z (the project report's order). A
# normal shared by two pairs is listed under both. Columns as in the
# project report's flagged table, with the page number first.
#
pair_flag_table <- function(hits, pairing, info) {
    pairing |>
        mutate(PAGE = row_number()) |>
        pmap(\(...) {
            p <- list(...)
            hits |>
                filter(SAMPLE %in% c(p$TUMOR_ID, p$NORMAL_ID, p$PAIR)) |>
                mutate(PAGE = p$PAGE)
        }) |>
        bind_rows() |>
        left_join(info |> select(METRIC, KIND, METRIC_LABEL = LABEL), by = "METRIC") |>
        transmute(
            Page = PAGE,
            Sample = if_else(TYPE == "Pair", LABEL, SAMPLE),
            Type = TYPE,
            Level = LEVEL,
            Metric = METRIC_LABEL,
            Value = format_value(VALUE, KIND, SCALE_BY),
            Median = format_value(MEDIAN, KIND, SCALE_BY),
            Limit = format_value(LIMIT, KIND, SCALE_BY),
            Percentile = sprintf("%.1f%%", 100 * PCTILE)
        )
}

#
# All pair pages. inputs: a list with pairing, projLong (with the pair
# metrics: FACETS, Tempo, Manta), bgLong, bgSamples (SAMPLE, TYPE), hits,
# limLong, info, scanned, keyDrop, pairDist (pair_distributions), dists
# (project_sample_dists), mvlh (project_gene_mvlh), bgCoverage,
# bgInsertSize, bgDupHist, bgGcBias, bgMvlh (the background's dist
# tables; empty when the database has none), qcdbVersion,
# genes (gene resources), sexTbl, sampleMeta, and design (TRUE for
# design mode).
#
pair_report_pages <- function(inputs) {
    with(inputs, {
        sampleTypes <- bind_rows(
            pairing |> transmute(SAMPLE = TUMOR_ID, TYPE = "Tumor"),
            pairing |> transmute(SAMPLE = NORMAL_ID, TYPE = "Normal")
        ) |>
            distinct()

        # Values: the project's metrics, pair metrics included, and the
        # depths Picard does not report
        depth <- target_depth_metrics(pairDist$coverage) |>
            inner_join(sampleTypes, by = "SAMPLE")
        projRows <- projLong |>
            filter(METRIC %in% c(PAIR_ROWS$METRIC, "HSM_MEDIAN_TARGET_COVERAGE", "ALFRED_MEDIANINSERTSIZE")) |>
            select(SAMPLE, TYPE, METRIC, VALUE)
        vals <- bind_rows(
            projRows,
            depth |> anti_join(projRows, by = c("SAMPLE", "METRIC"))
        ) |>
            left_join(hits |> select(SAMPLE, METRIC, LEVEL), by = c("SAMPLE", "METRIC")) |>
            # The project report does not flag FACETS QC; a fail is shaded
            # as a FAIL so it shows on the page
            mutate(LEVEL = if_else(METRIC == "FACETS_facets_qc" & coalesce(VALUE == 0, FALSE), "FAIL", LEVEL))

        # Background: the same metrics, and the depths from the
        # background's coverage histograms
        bgDepth <- target_depth_metrics(bgCoverage) |>
            inner_join(bgSamples |> select(SAMPLE, TYPE), by = "SAMPLE") |>
            select(TYPE, METRIC, VALUE)
        bgRows <- bgLong |>
            filter(METRIC %in% PAIR_ROWS$METRIC) |>
            select(TYPE, METRIC, VALUE)
        boxes <- bind_rows(bgRows, bgDepth |> filter(!METRIC %in% bgRows$METRIC)) |>
            background_boxes(info)

        # Limits: only of the metrics the project report scans, in the
        # types it judges them in
        lims <- limLong |>
            filter(METRIC %in% PAIR_ROWS$METRIC, METRIC %in% scanned) |>
            anti_join(keyDrop, by = c("METRIC", "TYPE"))

        # The flagged metrics that are not table rows (drawn below the
        # plots): the project's values with their flags, the background
        # and the limits
        flagMetrics <- setdiff(unique(hits$METRIC), PAIR_ROWS$METRIC)
        flagVals <- projLong |>
            filter(METRIC %in% flagMetrics) |>
            distinct(SAMPLE, TYPE, METRIC, .keep_all = TRUE) |>
            select(SAMPLE, TYPE, METRIC, VALUE) |>
            left_join(hits |> distinct(SAMPLE, METRIC, LEVEL), by = c("SAMPLE", "METRIC"))
        flagBg <- bgLong |>
            filter(METRIC %in% flagMetrics) |>
            select(TYPE, METRIC, VALUE)
        flagBoxes <- background_boxes(flagBg, info)
        flagLims <- limLong |>
            filter(METRIC %in% flagMetrics, METRIC %in% scanned) |>
            anti_join(keyDrop, by = c("METRIC", "TYPE"))

        covBin <- 5
        insBin <- 10
        bgCovSamples <- bgCoverage |> distinct(SAMPLE)
        covMax <- c(upper_quantile(pairDist$coverage, "COVERAGE", "HQ_COVERAGE_COUNT"),
                    upper_quantile(bgCoverage, "COVERAGE", "HQ_COVERAGE_COUNT")) |>
            quantile(0.9, names = FALSE) |>
            (\(x) min(1000, ceiling(x / 50) * 50))()
        insMax <- c(upper_quantile(pairDist$insertSize, "InsertSize", "Count"),
                    upper_quantile(bgInsertSize, "InsertSize", "Count")) |>
            quantile(0.9, names = FALSE) |>
            (\(x) min(1000, ceiling(x / 100) * 100))()
        covBinned <- bin_fractions(pairDist$coverage, "COVERAGE", "HQ_COVERAGE_COUNT", covBin, covMax)
        insBinned <- bin_fractions(pairDist$insertSize, "InsertSize", "Count", insBin, insMax)
        covBand <- bin_fractions(bgCoverage, "COVERAGE", "HQ_COVERAGE_COUNT", covBin, covMax) |>
            background_band(bgSamples |> select(SAMPLE, TYPE))
        insBand <- bin_fractions(bgInsertSize, "InsertSize", "Count", insBin, insMax) |>
            background_band(bgSamples |> select(SAMPLE, TYPE))

        # GC bias and duplicate frequency: the pair's curves, and the
        # background's band per type
        gcBand <- gc_bias_bins(bgGcBias) |> background_band(bgSamples |> select(SAMPLE, TYPE), "Y")
        dupBand <- dup_fractions(bgDupHist) |> background_band(bgSamples |> select(SAMPLE, TYPE), "Y")
        noBg <- glue("No QC background in database version {qcdbVersion}")
        notes <- list(
            gc = if (nrow(bgGcBias) == 0) glue("No GC table in QC database version {qcdbVersion}"),
            dup = if (nrow(bgDupHist) == 0) noBg,
            mvlh = if (nrow(bgMvlh) == 0) noBg
        )

        # Missed-variant likelihood: tumors only (Tempo is a somatic
        # pipeline), over the OncoKB genes, from project_gene_mvlh
        labels <- info |> select(METRIC, LABEL, KIND)
        ctx <- list(
            boxes = boxes, vals = vals, lims = lims, hits = hits, labels = labels, genes = genes,
            covBinned = covBinned, insBinned = insBinned, covBand = covBand, insBand = insBand,
            covBin = covBin, insBin = insBin, covMax = covMax, insMax = insMax,
            gcProj = gc_bias_bins(dists$target_gc_bias), gcBand = gcBand,
            dupProj = dup_fractions(dists$fastp_dup_hist), dupBand = dupBand, notes = notes,
            mvlh = mvlh, bgMvlh = bgMvlh |> select(SAMPLE, GENE, MVLH),
            flagVals = flagVals, flagBg = flagBg, flagBoxes = flagBoxes, flagLims = flagLims, info = info,
            sexTbl = sexTbl, sampleMeta = sampleMeta, design = isTRUE(inputs$design)
        )
        pages <- pairing |>
            pmap(\(...) pair_page(list(...), ctx))
        list(pages = pages, flagTable = pair_flag_table(hits, pairing, info), mvlh = mvlh, vals = vals)
    })
}
