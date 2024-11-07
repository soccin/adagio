get_sm_tag<-function(bam) {
    #
    # The sample name must be exactly what is in the SM: tag
    #
    hh=Rsamtools::scanBamHeader(bam)[[1]]
    gsub("SM:","",grep("SM:",hh$text[names(hh$text)=="@RG"][1][[1]],value=T))
}

argv=commandArgs(trailing=T)

if(len(argv)<1) {
    cat("\n\n  usage: wgsBAM2Tempo.R bam1 [bam2 ...]\n\n")
    quit()
}

mapping=tibble::tibble(
    SAMPLE=purrr::map_vec(argv,get_sm_tag),
    TARGET="wgs",
    BAM=fs::path_real(argv),
    BAI=fs::path_real(gsub("\\.bam$",".bam.bai",argv))
)

readr::write_tsv(mapping,"mapping_bam_tempo.tsv")
readr::write_tsv(
    tibble::tribble(~NORMAL_ID,~TUMOR_ID),
    "pairing_bam_tempo.tsv"
)