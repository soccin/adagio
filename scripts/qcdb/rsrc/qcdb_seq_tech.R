#
# qcdb_seq_tech.R
#
# Sequencer technology of each sample, from the instrument ID in its
# fastp file names: SAMPLE@INSTRUMENT@RUN@FLOWCELL@LANE_001.fastp.json.
# The QC database keeps INSTRUMENT@RUN@FLOWCELL@LANE as
# dist$fastp_lanes$LANE_TAG.
#
# Many Picard metrics differ between technologies (strand balance,
# mismatch and error rates, % aligned, ...), so qcReport02.R compares a
# project only with background samples of its own technology.
#
# Instrument ID prefix (letters before the serial number) to
# technology. An instrument not listed is "Unknown"; a sample with lanes
# from more than one technology is "Mixed". Samples on several
# instruments of one technology keep it.
#
SEQ_TECH_PREFIXES <- c(
    LH = "NovaSeq X",
    A = "NovaSeq 6000"
)

instrument_tech <- function(instrument) {
    prefix <- str_extract(instrument, "^[A-Za-z]+(?=\\d)")
    coalesce(unname(SEQ_TECH_PREFIXES[prefix]), "Unknown")
}

# "LH = NovaSeq X, A = NovaSeq 6000", for reports
seq_tech_rules <- function() {
    str_c(names(SEQ_TECH_PREFIXES), " = ", SEQ_TECH_PREFIXES, collapse = ", ")
}

# Lane table (SAMPLE, LANE_TAG) from fastp JSON file names, split as
# read_fastp() splits them
fastp_lane_tags <- function(files) {
    parts <- basename(files) |>
        str_remove("\\.fastp\\.json$") |>
        str_split("@")
    tibble(
        SAMPLE = map_chr(parts, 1),
        LANE_TAG = map_chr(parts, \(p) str_c(p[-1], collapse = "@"))
    )
}

# lanes: SAMPLE and LANE_TAG. One row per sample: SEQ_TECH and
# INSTRUMENT (every instrument of the sample, "+" separated)
sample_seq_tech <- function(lanes) {
    lanes |>
        distinct(SAMPLE, LANE_TAG) |>
        mutate(INSTRUMENT = word(LANE_TAG, 1, sep = "@"), TECH = instrument_tech(INSTRUMENT)) |>
        summarize(
            SEQ_TECH = if (n_distinct(TECH) == 1) TECH[1] else "Mixed",
            INSTRUMENT = str_c(sort(unique(INSTRUMENT)), collapse = "+"),
            .by = SAMPLE
        )
}
