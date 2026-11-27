#
# qc_plots.R
#
# Stacked horizontal box plots of QC metrics: the QC background as one
# box per type (Tumor, Normal, or Pair) and the project's samples as
# points over the box of their type. Used by qcReport02.R; needs
# qc_metric_info.R.
#
# Plot style: colors, marks, theme and axis rules follow the tumor/normal
# QC plot style guide (STYLE_GUIDE_TN_QC.md).
#

suppressPackageStartupMessages({
    library(patchwork)
    library(ggrepel)
})

TN_COLORS <- c(Tumor = "#C0392B", Normal = "#4F81BD")
TYPE_COLORS <- c(TN_COLORS, Pair = "grey60")
# Rings and limit lines: dark yellow WARN, dark red FAIL
LEVEL_COLORS <- c(WARN = "#C79A00", FAIL = "#9B1B1B")
LIMIT_BASE_COLOR <- "grey80"
LIMIT_WIDTH <- 0.75

N_LABEL <- 4
PANELS_PER_PAGE <- 4
MIN_PCT_AXIS <- 0.10

#
# Metric list files: one name (or pattern) per line, # starts a comment
#
read_metric_list <- function(file) {
    read_lines(file) |>
        str_remove("#.*$") |>
        str_trim() |>
        discard(\(x) x == "")
}

#
# Metric list with an optional type after the name ("METRIC Tumor"):
# one row per line, METRIC and TYPE (Tumor, Normal, or NA for every
# type)
#
read_typed_metric_list <- function(file) {
    parts <- read_metric_list(file) |> str_split("\\s+")
    if (any(lengths(parts) > 2)) {
        stop(glue("{file}: a line holds a metric name and at most one type"), call. = FALSE)
    }
    tbl <- tibble(METRIC = map_chr(parts, 1), TYPE = map_chr(parts, \(p) p[2]))
    badTypes <- setdiff(na.omit(tbl$TYPE), c("Tumor", "Normal"))
    if (len(badTypes) > 0) {
        stop(glue("{file}: the type must be Tumor or Normal, not {str_c(badTypes, collapse = ', ')}"),
             call. = FALSE)
    }
    tbl
}

qc_theme <- function(baseSize = 11, titleSize = 10) {
    theme_minimal(base_size = baseSize) +
        theme(
            panel.grid.minor = element_blank(),
            panel.grid.major.x = element_blank(),
            panel.grid.major.y = element_line(colour = "grey88", linewidth = 0.3),
            panel.border = element_rect(colour = "black", fill = NA, linewidth = 0.6),
            axis.ticks = element_line(colour = "black", linewidth = 0.4),
            plot.title = element_text(size = titleSize, face = "bold"),
            plot.title.position = "plot"
        )
}

page_theme <- function(subtitleSize = 9) {
    theme(
        plot.title = element_text(size = 14),
        plot.subtitle = element_text(colour = "grey30", size = subtitleSize),
        plot.caption = element_text(colour = "grey40", size = 7.5)
    )
}

# Ticks at 1-2-5 steps; 1-9 steps when the range is under about a decade
log_breaks <- function(lo, hi) {
    k <- floor(log10(lo)):ceiling(log10(hi))
    b <- as.vector(outer(c(1, 2, 5), 10^k))
    if (sum(b >= lo & b <= hi) < 3) b <- as.vector(outer(1:9, 10^k))
    b
}

pct_label_each <- function(x) {
    map_chr(x * 100, \(v) str_c(format(v, scientific = FALSE, drop0trailing = TRUE, digits = 6, trim = TRUE), "%"))
}

# 0-100% when the data span more than 50 points, else the data range
# widened by 12.5% of the span on each side, kept inside 0-100%. The
# result is at least minWidth wide (shifted to stay inside 0-100%).
frac_range <- function(v, minWidth = MIN_PCT_AXIS) {
    span <- diff(range(v))
    if (span > 0.5) return(c(0, 1))
    r <- c(max(0, min(v) - 0.125 * span), min(1, max(v) + 0.125 * span))
    if (diff(r) < minWidth) {
        r <- mean(r) + c(-1, 1) * minWidth / 2
        r <- r - min(0, r[1]) - max(0, r[2] - 1)
    }
    r
}

#
# Axis for one metric: a transform applied to the values before
# plotting, the x scale, a suffix for the panel title, its type
# (logodds, log or linear), and which limit values can be drawn on it. dataValues: all background and project
# values, used to choose the axis type. rangeValues: what the axis must
# show (box whisker ends, project values and the limits).
#
# Fractions get a log axis when they span more than two orders of
# magnitude, and a log-odds axis (near 100%) or log axis (near 0%) when
# a linear axis would squeeze the background boxes to under 3% of its
# width. Fractions that all sit below 10% also get a log axis. The rest
# get a linear percent axis at least 10 points wide.
#
axis_spec <- function(info, bg, dataValues, rangeValues) {
    kind <- info$KIND
    scaleBy <- info$SCALE_BY
    d <- dataValues / scaleBy
    d <- d[is.finite(d)]
    v <- rangeValues / scaleBy
    v <- v[is.finite(v)]
    identityTx <- \(x) x / scaleBy
    always <- \(x) rep(TRUE, len(x))
    positive <- \(x) x > 0
    ratio <- if (min(d) > 0) max(d) / min(d) else Inf
    pctLabels <- scales::label_percent(drop0trailing = TRUE)

    if (kind %in% PERCENT_KINDS) {
        iqrWidth <- bg |>
            summarize(W = IQR(VALUE / scaleBy, na.rm = TRUE), .by = TYPE) |>
            pull(W) |>
            max()
        # Over the data and the limits: a fixed limit far from the data
        # (concordance 95%) widens the axis
        squeezed <- iqrWidth < 0.03 * diff(frac_range(c(d, v), minWidth = 0))
        nearOne <- median(bg$VALUE / scaleBy, na.rm = TRUE) > 0.5

        if (squeezed && nearOne) {
            pp <- c(1e-4, 1e-3, 0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 0.8, 0.9, 0.95, 0.98, 0.99,
                    0.995, 0.998, 0.999, 0.9995, 0.9999)
            return(list(
                tx = \(x) {
                    p <- pmin(pmax(x / scaleBy, LOGIT_EPS), 1 - LOGIT_EPS)
                    p / (1 - p)
                },
                scale = scale_x_log10(breaks = pp / (1 - pp), labels = pct_label_each(pp)),
                suffix = " (log-odds axis)",
                type = "logodds",
                valid = always
            ))
        }
        # A linear axis would be at least MIN_PCT_AXIS wide; when all the
        # values sit below that, a log axis shows their spread instead
        small <- max(v) < MIN_PCT_AXIS && min(d) > 0
        if (ratio > 100 || (squeezed && !nearOne) || small) {
            floorV <- 1e-4
            lo <- max(min(v), floorV)
            return(list(
                tx = \(x) pmax(x / scaleBy, floorV),
                scale = scale_x_log10(breaks = log_breaks(lo, max(v)), labels = pctLabels),
                suffix = " (log scale)",
                type = "log",
                valid = \(x) x / scaleBy >= floorV
            ))
        }
        return(list(
            tx = identityTx,
            scale = scale_x_continuous(labels = pctLabels),
            xlim = frac_range(v),
            suffix = "",
            type = "linear",
            valid = always
        ))
    }

    labels <- switch(kind,
        bp = scales::label_number(suffix = " bp", big.mark = ","),
        cov = scales::label_number(suffix = "x", big.mark = ","),
        count = scales::label_number(scale_cut = scales::cut_short_scale(), drop0trailing = TRUE),
        waiver()
    )
    if (ratio > 100 && is.finite(ratio)) {
        return(list(
            tx = identityTx,
            scale = scale_x_log10(breaks = log_breaks(min(v), max(v)), labels = labels),
            suffix = " (log scale)",
            type = "log",
            valid = positive
        ))
    }
    if (kind == "cov") {
        return(list(
            tx = identityTx,
            scale = scale_x_continuous(labels = labels),
            xlim = c(0, max(v) * 1.05),
            suffix = "",
            type = "linear",
            valid = always
        ))
    }
    list(tx = identityTx, scale = scale_x_continuous(labels = labels), suffix = "", type = "linear", valid = always)
}

#
# One panel. info: the metric's row of metric_info(). bg: TYPE, VALUE
# (background). proj: SAMPLE, LABEL, TYPE, VALUE, Z, LEVEL, IS_BAD
# (project). lims: TYPE, LEVEL, LIMIT (WARN and FAIL limits on the bad
# side). fillTypes: the types in the page legend.
#
# Flagged samples get a ring, dark yellow for WARN and dark red for
# FAIL; up to N_LABEL of them (FAIL first, then largest |z|) also get a
# label.
#
qc_panel <- function(info, bg, proj, lims, fillTypes) {
    # One row for pairs, or for a metric limited to one type
    rows <- if (any(bg$TYPE == "Pair")) "Pair" else intersect(c("Normal", "Tumor"), bg$TYPE)
    yLimits <- if (len(rows) == 1) c(0, 2) else c(0.5, len(rows) + 0.5)
    lims <- lims |> filter(TYPE %in% rows)
    # Background outliers are not drawn, so the axis covers only the
    # whisker ends of each box (1.5 IQR, as geom_boxplot)
    whiskers <- bg |>
        filter(TYPE %in% rows) |>
        reframe(VALUE = boxplot.stats(VALUE)$stats[c(1, 5)], .by = TYPE) |>
        pull(VALUE)
    ax <- axis_spec(info, bg, c(bg$VALUE, proj$VALUE), c(whiskers, proj$VALUE, lims$LIMIT))

    bg <- bg |>
        filter(TYPE %in% rows) |>
        mutate(X = ax$tx(VALUE), Y = match(TYPE, rows))
    lims <- lims |>
        filter(ax$valid(LIMIT)) |>
        mutate(X = ax$tx(LIMIT), Y = match(TYPE, rows))
    set.seed(1)
    proj <- proj |>
        filter(TYPE %in% rows, is.finite(VALUE)) |>
        mutate(
            X = ax$tx(VALUE),
            Y = match(TYPE, rows) + runif(n(), -0.12, 0.12),
            TYPE = factor(TYPE, levels = fillTypes)
        )
    flagged <- proj |>
        filter(IS_BAD) |>
        mutate(RING = LEVEL_COLORS[LEVEL])
    labeled <- flagged |>
        arrange(LEVEL != "FAIL", desc(abs(Z))) |>
        head(N_LABEL)
    lims <- lims |> mutate(LINE = LEVEL_COLORS[LEVEL])

    # limit lines: a solid grey line with the dotted level-colored line
    # on top. "11": dots as long as the gaps; R's "dotted" (13) leaves
    # gaps three times the dot length
    # A single-row panel (Pair, or one type) has the height of two rows; its lines
    # span most of the panel rather than one row's band
    halfHeight <- if (len(rows) == 1) 0.85 else 0.4
    limitSegment <- aes(x = X, xend = X, y = Y - halfHeight, yend = Y + halfHeight)

    ggplot(mapping = aes(x = X, y = Y)) +
        geom_segment(data = lims, limitSegment, colour = LIMIT_BASE_COLOR, linewidth = LIMIT_WIDTH) +
        geom_segment(data = lims, aes(x = X, xend = X, y = Y - halfHeight, yend = Y + halfHeight, colour = LINE),
                     linetype = "11", linewidth = LIMIT_WIDTH) +
        geom_boxplot(
            data = bg,
            aes(group = TYPE, fill = TYPE),
            orientation = "y",
            width = 0.22,
            alpha = 0.3,
            colour = "grey65",
            linewidth = 0.4,
            # background outliers are neither drawn nor counted in the axis range
            outliers = FALSE,
            show.legend = FALSE
        ) +
        # show.legend = TRUE draws every type in the legend, so pair and
        # tumor/normal panels share one legend on the page
        geom_point(
            data = proj,
            aes(fill = TYPE),
            shape = 21,
            colour = "black",
            stroke = 0.5,
            size = 2.2,
            show.legend = TRUE
        ) +
        geom_point(data = flagged, aes(colour = RING), shape = 21, fill = NA, size = 5, stroke = 1.6) +
        geom_label_repel(
            data = labeled,
            aes(label = LABEL),
            size = 3,
            fontface = "bold",
            colour = "black",
            fill = "white",
            label.size = 0.3,
            box.padding = 0.6,
            min.segment.length = 0,
            segment.colour = "grey30",
            segment.size = 0.6,
            max.overlaps = Inf,
            seed = 1
        ) +
        scale_fill_manual(values = TYPE_COLORS, limits = fillTypes, drop = FALSE, name = "Project samples") +
        scale_colour_identity() +
        scale_y_continuous(breaks = seq_along(rows), labels = rows, limits = yLimits, expand = expansion(0)) +
        ax$scale +
        # zoom, not scale limits: values outside still count in the box stats
        coord_cartesian(xlim = ax$xlim) +
        labs(title = str_c(info$LABEL, ax$suffix), x = NULL, y = NULL) +
        qc_theme(11, 10) +
        theme(axis.ticks.y = element_blank(), axis.text.y = element_text(size = 9))
}

#
# Pages of panels, one column. A page holds PANELS_PER_PAGE panels of
# height 1; panelHeight > 1 makes the panels taller and puts fewer on a
# page. The rest of each page is blank, so panel heights match across
# pages.
#
qc_pages <- function(metrics, info, bgLong, projLong, limLong, title, subtitle, caption = NULL,
                     panelHeight = 1) {
    if (len(metrics) == 0) return(list())
    perPage <- floor(PANELS_PER_PAGE / panelHeight)
    chunks <- split(metrics, ceiling(seq_along(metrics) / perPage))
    imap(unname(chunks), function(chunk, i) {
        pageTypes <- bgLong |>
            filter(METRIC %in% chunk) |>
            distinct(TYPE) |>
            pull(TYPE)
        fillTypes <- intersect(c("Tumor", "Normal", "Pair"), pageTypes)
        panels <- map(chunk, \(m) qc_panel(
            info |> filter(METRIC == m),
            bgLong |> filter(METRIC == m),
            projLong |> filter(METRIC == m),
            limLong |> filter(METRIC == m),
            fillTypes
        ))
        blank <- PANELS_PER_PAGE - panelHeight * len(panels)
        heights <- rep(panelHeight, len(panels))
        if (blank > 0.01) {
            panels <- c(panels, list(plot_spacer()))
            heights <- c(heights, blank)
        }
        pageCaption <- caption
        if ("Pair" %in% fillTypes) {
            pageCaption <- str_c(c(pageCaption, "Pair rows: one point per tumor/normal pair, labeled with the tumor ID."),
                                 collapse = "\n")
        }
        wrap_plots(panels, ncol = 1, heights = heights, guides = "collect") +
            plot_annotation(
                title = glue("{title}, page {i} of {len(chunks)}"),
                subtitle = subtitle,
                caption = pageCaption,
                theme = page_theme(9)
            ) &
            theme(legend.position = "bottom")
    })
}

#
# Concordance and sex page: the Conpair panels (metrics), then the sex
# plot beside the text of the sex rules, then the first maxRows rows of
# the sex table (one row per pair). The rest of the table continues on
# table pages.
#
concordance_pages <- function(metrics, info, bgLong, projLong, limLong, sexPlotFn, sexTbl, sexText,
                              title, subtitle, caption = NULL, maxRows = 8) {
    fillTypes <- c("Tumor", "Normal", "Pair")
    panels <- map(metrics, \(m) qc_panel(
        info |> filter(METRIC == m),
        bgLong |> filter(METRIC == m),
        projLong |> filter(METRIC == m),
        limLong |> filter(METRIC == m),
        fillTypes
    ))
    rules <- wrap_elements(full = grid::textGrob(
        sexText, x = 0.04, y = 0.95, just = c("left", "top"),
        gp = grid::gpar(fontsize = 8, col = "grey20", lineheight = 1.15)
    ))
    sexRow <- wrap_plots(sexPlotFn(fillTypes), rules, nrow = 1, widths = c(1.15, 1))
    firstRows <- head(sexTbl, maxRows)
    rest <- tail(sexTbl, -maxRows)
    tableNote <- if (nrow(rest) > 0) glue("Sex table: first {maxRows} of {nrow(sexTbl)} pairs, continued on the next page") else NULL
    tableBlock <- wrap_elements(full = table_grob(firstRows, baseSize = 7))
    heights <- c(rep(1, len(panels)), 1.25, PANELS_PER_PAGE - len(panels) - 1.25)
    pageCaption <- str_c(c(caption, "Pair rows: one point per tumor/normal pair, labeled with the tumor ID.",
                           tableNote), collapse = "\n")
    first <- wrap_plots(c(panels, list(sexRow, tableBlock)), ncol = 1, heights = heights, guides = "collect") +
        plot_annotation(title = title, subtitle = subtitle, caption = pageCaption, theme = page_theme(9)) &
        theme(legend.position = "bottom")
    c(list(first), table_pages(rest, glue("{title}: sex table, continued"), NULL))
}

#
# Text pages: a table (tibble) split into pages of maxRows rows
#
# A table (tibble) as a grob placed at the top left of its area
# rather than centered
table_grob <- function(tbl, baseSize = 8) {
    tt <- gridExtra::ttheme_minimal(
        base_size = baseSize,
        colhead = list(fg_params = list(fontface = "bold", hjust = 0, x = 0.02)),
        core = list(fg_params = list(hjust = 0, x = 0.02))
    )
    tg <- gridExtra::tableGrob(tbl, rows = NULL, theme = tt)
    tg$vp <- grid::viewport(
        x = 0, y = 1, just = c("left", "top"),
        width = sum(tg$widths), height = sum(tg$heights)
    )
    tg
}

table_pages <- function(tbl, title, subtitle, maxRows = 40) {
    if (nrow(tbl) == 0) return(list())
    chunks <- split(tbl, ceiling(seq_len(nrow(tbl)) / maxRows))
    imap(unname(chunks), function(chunk, i) {
        tg <- table_grob(chunk)
        wrap_elements(full = tg) +
            plot_annotation(
                title = glue("{title}, page {i} of {len(chunks)}"),
                subtitle = subtitle,
                theme = page_theme(9)
            )
    })
}

text_page <- function(title, text) {
    wrap_elements(full = grid::textGrob(text, x = 0.05, y = 0.95, just = c("left", "top"),
                                        gp = grid::gpar(fontsize = 11))) +
        plot_annotation(title = title, theme = page_theme(9))
}

#
# One page with a whole table (tibble) in monospace text: rows split
# into side by side columns (up to 4), font sized so every row fits an
# 8.5 x 11 in page under a subtitle of a few lines
#
FIT_TEXT_W_PT <- 540
FIT_TEXT_H_PT <- 540
FIT_MAX_FONT <- 10

fit_table_page <- function(title, subtitle, tbl) {
    cells <- tbl |> mutate(across(everything(), as.character))
    widths <- map_int(names(cells), \(n) max(nchar(c(n, cells[[n]]))))
    fmt_row <- \(x) str_c(str_pad(x, widths, side = "right"), collapse = "  ")
    header <- fmt_row(names(cells))
    rows <- pmap_chr(cells, \(...) fmt_row(c(...)))

    # Monospace: a character is 0.6 em wide and a line 1.2 em high
    font_for <- \(k) min(
        FIT_MAX_FONT,
        FIT_TEXT_H_PT / (1.2 * (ceiling(len(rows) / k) + 2)),
        FIT_TEXT_W_PT / (0.6 * k * (nchar(header) + 4))
    )
    fonts <- map_dbl(1:4, font_for)
    nCol <- which.max(fonts)
    chunks <- split(rows, ceiling(seq_along(rows) / ceiling(len(rows) / nCol)))
    cols <- imap(unname(chunks), \(chunk, i) grid::textGrob(
        str_c(c(header, strrep("-", nchar(header)), chunk), collapse = "\n"),
        x = (i - 1) / nCol, y = 1, just = c("left", "top"),
        gp = grid::gpar(fontfamily = "mono", fontsize = fonts[nCol], lineheight = 1.2)
    ))
    wrap_elements(full = grid::gTree(children = do.call(grid::gList, cols))) +
        plot_annotation(title = title, subtitle = subtitle, theme = page_theme(10))
}
