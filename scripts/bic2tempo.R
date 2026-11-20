#!/usr/bin/env Rscript
mapfile=commandArgs(trailing=TRUE)[1]
pairfile=commandArgs(trailing=TRUE)[2]
targetName=commandArgs(trailing=TRUE)[3]

if(is.na(mapfile) || is.na(pairfile)) {
    cat("\n   usage: bic2tempo.R MAPPING_FILE.txt PAIRING_FILE.txt [TARGET]\n\n")
    quit()
}

if(is.na(targetName)) {
    cat("\n   TARGET not specified so idt_v2 being used as default\n\n")
    targetName="idt_v2"
}

suppressPackageStartupMessages({
    library(dplyr)
    library(purrr)
    library(readr)
    library(stringr)
})

map=read_tsv(mapfile,col_names=F,show_col_types = FALSE,progress=F) %>% mutate(X2=gsub("^s_","",X2))
pair=read_tsv(pairfile,col_names=F,show_col_types = FALSE,progress=F)  %>% mutate_all(~gsub("^s_","",.))

ms=map %>% distinct(X2) %>% pull
ps=unlist(pair) %>% unname %>% unique
samps=intersect(ms,ps)

badNames=grep("__|pool",samps,ignore.case=T,value=T)
if(len(badNames)>0) {
    cat("\n\n   Bad names found\n")
    cat("\n   ",paste(badNames,collapse="\n    "),"\n\n")
    cat("   Tempo does not work with names that contain:\n")
    cat("     - 'pool|Pool|POOL' (case ignore)\n")
    cat("     - '__' (double underscore)\n\n\n")
    rlang::abort()
}

map=map %>% filter(X2 %in% samps)

if(nrow(map)==0) {
    cat("\n\tSample ID miss match.\n\tNo common samples between pairing and mapping\n\n")
    rlang::abort("FATAL::ERROR")
}

#
# A pair with a sample that is not in the mapping would be dropped by
# Tempo with no message, so stop here and name it
#
droppedPairs=pair |> filter(!(X1 %in% samps & X2 %in% samps))

if(nrow(droppedPairs)>0) {
    cat("\n   Pairs with a sample that is not in the mapping file:\n\n")
    droppedPairs |>
        mutate(
            Missing=map2_chr(X1,X2,\(n,t) str_c(setdiff(c(n,t),samps),collapse=",")),
            Line=str_glue("     NORMAL={X1}  TUMOR={X2}  missing: {Missing}")
        ) |>
        pull(Line) |>
        cat(sep="\n")
    cat("\n   Fix the mapping or remove these pairs from the pairing file\n\n")
    rlang::abort("FATAL::ERROR")
}

#
# Each R1 file needs its R2 file (same name with _R2_). A sample with no
# R1 files would get no mapping rows and its pair would be dropped
#
pmap=list()
fastqErrors=character()

for(mi in map |> transpose()) {

    sid=gsub("^s_","",mi$X2)
    fastq1=sort(fs::dir_ls(mi$X4,recur=T,regex="_R1_\\d+.fastq.gz$"))
    fastq2=sort(fs::dir_ls(mi$X4,recur=T,regex="_R2_\\d+.fastq.gz$"))
    fastq2Expected=str_replace(fastq1,"_R1_(\\d+\\.fastq\\.gz)$","_R2_\\1")

    if(len(fastq1)==0) {
        fastqErrors=c(fastqErrors,str_glue("{sid}: no _R1_NNN.fastq.gz files in {mi$X4}"))
        next
    }

    if(len(fastq1)!=len(fastq2) || !all(fastq2Expected %in% fastq2)) {
        fastqErrors=c(
            fastqErrors,
            str_glue("{sid}: {len(fastq1)} R1 and {len(fastq2)} R2 files do not pair up in {mi$X4}")
        )
        next
    }

    pmap[[len(pmap)+1]]=tibble::tibble(
                            SAMPLE=sid,TARGET=targetName,
                            FASTQ_PE1=fastq1,FASTQ_PE2=fastq2Expected
                        )

}

if(len(fastqErrors)>0) {
    cat("\n   FASTQ problems:\n\n")
    cat(str_c("     ",fastqErrors),sep="\n")
    cat("\n")
    rlang::abort("FATAL::ERROR")
}

pmap=bind_rows(pmap)
tpair=pair %>% mutate_all(~gsub("^s_","",.)) %>% select(NORMAL_ID=X1,TUMOR_ID=X2)
#requestId=stringr::str_extract(basename(pmap$FASTQ_PE1[1]),"_IGO_([^/]*)_\\d+_S",group=T)

write_tsv(tpair,"inputTempo_pairing.tsv")
write_tsv(pmap,"inputTempo_mapping.tsv")


