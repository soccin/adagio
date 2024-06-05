require(tidyverse)
require(ggsci)

projectNo=basename(fs::dir_ls("out"))
cohortDir=file.path("out",projectNo,"cohort_level")
sampleDir=file.path("out",projectNo,"somatic")

x11 = function (...) grDevices::x11(...,type='cairo')

dir_ls<-function(dir,re) {
    fs::dir_ls(dir,recur=T,regex=re)
}


read_tsv_quiet<-function(fileName) {
    read_tsv(fileName,show_col_types = FALSE,progress=F)
}

sampDat=read_tsv_quiet(dir_ls(cohortDir,"sample_data.txt"))
nSamps=nrow(sampDat)

if(nSamps==1) {

    d2=read_tsv_quiet(dir_ls(sampleDir,"contamination.txt")) %>%
        mutate(Contamination=Contamination/100)

    d1=read_tsv_quiet(dir_ls(sampleDir,"concordance.txt")) %>%
        rename(Sample_ID=concordance) %>%
        rename(Concordance=2) %>%
        mutate(QC=case_when(Concordance<90 ~ "FAIL", Concordance<95 ~ "WARN", T ~ "PASS"))

    pg1=d1 %>% ggplot(aes(Sample_ID,Concordance,fill=QC)) +
        theme_light(14) +
        geom_col() +
        coord_flip() +
        scale_fill_nejm() +
        labs(title=projectNo,subtitle="Conpair - Concordance")

    pg2=d2 %>% ggplot(aes(Sample_ID,Contamination,fill=Sample_Type)) +
        theme_light(14) +
        geom_col(position="dodge") +
        coord_flip() +
        scale_fill_jama() +
        scale_y_continuous(limits=c(0,1/100),labels = scales::percent_format(accuracy = .01),breaks=(0:10)/1000) +
        geom_hline(yintercept=.005,color="gold4",alpha=.5,linewidth=3) +
        labs(title=projectNo,subtitle="Conpair - Contamination")



}else{

    d1=read_tsv_quiet(dir_ls(cohortDir,"concordance_qc.txt"))
    d2=read_tsv_quiet(dir_ls(cohortDir,"contamination_qc.txt"))
        mutate(Contamination=Contamination/100)

    pg2=d2 %>%
        mutate(Pair=gsub("__","\n",Pair)) %>%
        ggplot(aes(Pair,Contamination,fill=Sample_Type)) +
            theme_light(14) +
            geom_col(position="dodge") +
            coord_flip() +
            scale_fill_jama() +
            scale_y_continuous(limits=c(0,1/100),labels = scales::percent_format(accuracy = .01),breaks=(0:10)/1000) +
            geom_hline(yintercept=.005,color="gold4",alpha=.5,linewidth=3) +
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


}

pdf(file=cc("Proj",projectNo,"qcRpt01.pdf"),width=11,height=8.5)
print(pg1)
print(pg2)
dev.off()
