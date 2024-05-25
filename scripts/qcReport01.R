require(tidyverse)
require(ggsci)

projectNo=basename(fs::dir_ls("out"))
d1=read_tsv("out/B-101-860-a/cohort_level/default_cohort/concordance_qc.txt")
d2=read_tsv("out/B-101-860-a/cohort_level/default_cohort/contamination_qc.txt")

pg2=d2 %>%
    mutate(Pair=gsub("__","\n",Pair)) %>%
    ggplot(aes(Pair,Contamination,fill=Sample_Type)) +
        theme_light(14) +
        geom_col(position="dodge") +
        coord_flip() +
        scale_y_log10() +
        scale_fill_jama() +
        labs(title=projectNo,subtitle="Conpair - Contamination")

pg1=d1 %>%
    mutate(Pair=gsub("__","\n",Pair)) %>%
    mutate(QC=case_when(Concordance<90 ~ "FAIL", Concordance<95 ~ "WARN", T ~ "PASS")) %>%
    ggplot(aes(Pair,Concordance,fill=QC)) +
    theme_light(14) +
    geom_col() +
    coord_flip() +
    scale_fill_nejm() +
    labs(title=projectNo,subtitle="Conpair - Concordance")

pdf(file=cc("Proj",projectNo,"qcRpt01.pdf"),width=11,height=8.5)
print(pg1)
print(pg2)
dev.off()
