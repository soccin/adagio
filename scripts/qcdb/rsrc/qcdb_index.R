#
# qcdb_index.R
#
# Find a QC background database. The .rds files are not in git; the
# tracked index assets/qcdb/qcdb_index.tsv (ASSAY, VERSION, DATE, PATH)
# lists where each one is stored. VERSION is the build date as yymmdd;
# DATE is the same date as YYYY-MM-DD.
#

read_qcdb_index <- function(adagio) {
    file.path(adagio, "assets", "qcdb", "qcdb_index.tsv") |>
        read_tsv(col_types = cols(.default = "c"), show_col_types = FALSE)
}

#
# Path to the database for an assay: the newest version in the index,
# or the given version. A non-NULL qcdb (for example from a --qcdb
# option) is returned as is.
#
find_qcdb <- function(adagio, assay, version = NULL, qcdb = NULL) {
    if (!is.null(qcdb)) {
        if (!fs::file_exists(qcdb)) stop(glue("QC database not found: {qcdb}"), call. = FALSE)
        return(qcdb)
    }
    hits <- read_qcdb_index(adagio) |> filter(ASSAY == assay)
    if (!is.null(version)) hits <- hits |> filter(VERSION == version)
    if (nrow(hits) == 0) {
        stop(glue("No QC database for assay {assay} in assets/qcdb/qcdb_index.tsv"), call. = FALSE)
    }
    path <- hits |> arrange(desc(VERSION)) |> slice(1) |> pull(PATH)
    if (!fs::file_exists(path)) stop(glue("QC database in index not found: {path}"), call. = FALSE)
    path
}

load_qcdb <- function(adagio, assay, version = NULL, qcdb = NULL) {
    find_qcdb(adagio, assay, version, qcdb) |> readRDS()
}
