suppressPackageStartupMessages({require(tidyverse)})

bams=tibble(BAM=scan("listOfBams","",quiet=T)) %>%
    mutate(SAMPLE=basename(BAM)%>%gsub(".smap.*","",.))

cov=fs::dir_ls("../out/metrics",recur=T,regex=".smap.wgs.txt$") %>%
    map(read_tsv,comment="#",n_max=1,show_col_types = FALSE,progress=F) %>%
    bind_rows(.id="SAMPLE") %>%
    mutate(SAMPLE=basename(SAMPLE)%>%gsub(".smap.*","",.)) %>%
    select(SAMPLE,MEAN_COVERAGE) %>%
    mutate(TYPE=ifelse(grepl("-N$",SAMPLE),"Normal","Tumor")) %>%
    mutate(P=pmin(1,ifelse(TYPE=="Normal",30,60)/MEAN_COVERAGE))

argv=left_join(bams,cov,by = join_by(SAMPLE)) %>% select(BAM,P)

for(ai in transpose(argv)) {

    cat(ai$BAM,ai$P,"\n")

}
