# fix_names<-function(ss) {
#     ifelse(grepl("^[0-9]",ss),cc("s",ss),ss)
# }

require(tidyverse)
argv=commandArgs(trailing=T)

R1=fs::dir_ls(argv,recur=T,regex=".*_R1_.*fastq.gz") %>% map_vec(fs::path_real) %>% sort
R2=fs::dir_ls(argv,recur=T,regex=".*_R2_.*fastq.gz") %>% map_vec(fs::path_real) %>% sort

if(!all(gsub("_R1_","",R1)==gsub("_R2_","",R2))) {
    cat("\n\n   R1-R2 mismatch\n\n")
    rlang::abort("ERROR")
}

sid=gsub("_IGO_.*","",basename(R1))

mapping=tibble(SAMPLE=sid,TARGET="wgs",FASTQ_PE1=R1,FASTQ_PE2=R2)

projNo=grep("Project_",strsplit(R1[1],"/")[[1]],value=T) %>% gsub("Project_","",.)

write_tsv(mapping,cc("inputTempo",projNo,"mapping.tsv"))
