get_sm_tag<-function(bam) {
    hh=Rsamtools::scanBamHeader(bam)[[1]]
    gsub("SM:","",grep("SM:",hh$text[names(hh$text)=="@RG"][1][[1]],value=T))
}

argv=commandArgs(trailing=T)

mapping=tibble::tibble(
    SAMPLE=purrr::map_vec(argv,get_sm_tag),
    TARGET="wgs",
    BAM=fs::path_real(argv),
    BAI=fs::path_real(gsub("\\.bam$",".bai",argv))
)

readr::write_tsv(mapping,"mapping_bam_tempo.tsv")
