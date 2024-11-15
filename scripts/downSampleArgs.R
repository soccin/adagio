suppressPackageStartupMessages({require(tidyverse)})

argv=commandArgs(trailing=T)
if(len(argv)!=2) {
    cat("\n\n   usage: downSampleArgs fileOfBamPaths metricsDir\n\n")
    quit()
}

bams=tibble(BAM=scan(argv[1],"",quiet=T)) %>%
    mutate(SAMPLE=basename(dirname(BAM))) %>%
    mutate(BAM=fs::path_expand(BAM))

cov=fs::dir_ls(argv[2],recur=T,regex="\\.wgs.txt$") %>%
    map(read_tsv,comment="#",n_max=1,show_col_types = FALSE,progress=F) %>%
    bind_rows(.id="SAMPLE") %>%
    mutate(SAMPLE=basename(dirname(SAMPLE))) %>%
    select(SAMPLE,MEAN_COVERAGE) %>%
    mutate(TYPE=ifelse(grepl("-N$",SAMPLE),"Normal","Tumor")) %>%
    mutate(P=pmin(1,ifelse(TYPE=="Normal",30,60)/MEAN_COVERAGE))

cmdargs=left_join(bams,cov,by = join_by(SAMPLE)) %>% select(BAM,P)

for(ai in transpose(cmdargs)) {

    cat(ai$BAM,ai$P,"\n")

}
