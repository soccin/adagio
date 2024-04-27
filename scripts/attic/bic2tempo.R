#!/usr/bin/env Rscript
mapfile=commandArgs(trailing=T)[1]
pairfile=commandArgs(trailing=T)[2]
targetName="idt"
if(is.na(mapfile) || is.na(pairfile)) {
    cat("\n   usage: bic2phoenix.R MAPPING_FILE.txt PAIRING_FILE.txt\n\n")
    quit()
}

suppressPackageStartupMessages({
    library(dplyr)
    library(purrr)
    library(readr)
})

map=read_tsv(mapfile,col_names=F,show_col_types = FALSE,progress=F)
pair=read_tsv(pairfile,col_names=F,show_col_types = FALSE,progress=F)

ms=map %>% distinct(X2) %>% pull
ps=unlist(pair) %>% unname %>% unique
samps=intersect(ms,ps)

map=map %>% filter(X2 %in% samps)
pair=pair %>% filter(X1 %in% samps & X2 %in% samps)

for(pi in pair |> transpose()) {

    pmap=list()
    mp=map %>% filter(X2==pi$X1 | X2==pi$X2)

    for(mi in mp |> transpose()) {

        sid=gsub("^s_","",mi$X2)
        fastq1=sort(fs::dir_ls(mi$X4,recur=T,regex="_R1_\\d+.fastq.gz$"))
        fastq2=sort(fs::dir_ls(mi$X4,recur=T,regex="_R2_\\d+.fastq.gz$"))

        pmap[[len(pmap)+1]]=tibble::tibble(
                                SAMPLE=sid,TARGET=targetName,
                                FASTQ_PE1=fastq1,FASTQ_PE2=fastq2
                            )

    }

    pmap=bind_rows(pmap)
    tumor=gsub("^s_","",pi$X2)
    normal=gsub("^s_","",pi$X1)

    ppi=tibble::tibble(NORMAL_ID=normal,TUMOR_ID=tumor)

    pairId=cc(tumor,"_",normal)
    write_tsv(ppi,paste0("inputTempo_",pairId,"_pairing.tsv"))
    write_tsv(pmap,paste0("inputTempo_",pairId,"_mapping.tsv"))

}

