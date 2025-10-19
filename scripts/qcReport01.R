require(tidyverse)
require(ggsci)

projectNo=basename(fs::dir_ls("out"))
cohortDir=file.path("out",projectNo,"cohort_level")
sampleDir=file.path("out",projectNo,"somatic")

x11 = function (...) grDevices::x11(...,type='cairo')

SDIR=get_script_dir()

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

    pg1=d1 %>%
    ggplot(aes(Sample_ID,Concordance,fill=QC)) +
        theme_light(14) +
        geom_col() +
        coord_flip() +
        scale_fill_nejm() +
        labs(title=projectNo,subtitle="Conpair - Concordance")

    pg2=d2 %>%
    ggplot(aes(Sample_ID,Contamination,fill=Sample_Type)) +
        theme_light(14) +
        geom_col(position="dodge") +
        coord_flip() +
        scale_fill_jama() +
        scale_y_continuous(limits=c(0,1/100),labels = scales::percent_format(accuracy = .01),breaks=(0:10)/1000) +
        geom_hline(yintercept=.005,color="gold4",alpha=.5,linewidth=3) +
        labs(title=projectNo,subtitle="Conpair - Contamination")



}else{

    d1=read_tsv_quiet(dir_ls(cohortDir,"concordance_qc.txt"))
    d2=read_tsv_quiet(dir_ls(cohortDir,"contamination_qc.txt")) %>%
        mutate(Contamination=Contamination/100)

    maxC=max(max(d2$Contamination),1/100)

    pg2=d2 %>%
        mutate(Pair=gsub("__","/",Pair)) %>%
        ggplot(aes(Pair,Contamination,fill=Sample_Type)) +
            theme_light(14) +
            geom_col(position="dodge") +
            coord_flip() +
            scale_fill_jama() +
            scale_y_continuous(limits=c(0,maxC),labels = scales::percent_format(accuracy = .01)) +
            geom_hline(yintercept=.005,color="gold4",alpha=.5,linewidth=3) +
            labs(title=projectNo,subtitle="Conpair - Contamination")

    pg1=d1 %>%
        mutate(Pair=gsub("__","/",Pair)) %>%
        mutate(QC=case_when(Concordance<90 ~ "FAIL", Concordance<95 ~ "WARN", T ~ "PASS")) %>%
        ggplot(aes(Pair,Concordance,fill=QC)) +
        theme_light(14) +
        geom_col() +
        coord_flip() +
        scale_fill_nejm() +
        labs(title=projectNo,subtitle="Conpair - Concordance")


}

typeMap=d2 %>% select(SAMPLE=Sample_ID,TYPE=Sample_Type,PAIR=Pair) %>% arrange(PAIR,TYPE,SAMPLE) %>% distinct(SAMPLE,TYPE)
Ng=round(nrow(typeMap)/12)
Nb=round(nrow(typeMap)/Ng)
typeMap=typeMap %>% mutate(R=floor((row_number()-1)/Nb))

hsmFiles=fs::dir_ls("out",recur=T,regex="hs_metrics.txt")
#
# WGS does not have hsmfiles
#
if(len(hsmFiles)>0) {

  hsm=fs::dir_ls("out",recur=T,regex="hs_metrics.txt") %>%
      map(read_tsv,comment="#",n_max=1,progress=F,show_col_types=F) %>%
      bind_rows(.id="PATH") %>%
      mutate(SAMPLE=basename(PATH)%>%gsub(".hs_metrics.*","",.)) %>%
      select(-PATH) %>%
      select(SAMPLE,everything()) %>%
      select(SAMPLE,MEAN_TARGET_COVERAGE,ZERO_CVG_TARGETS_PCT,PCT_TARGET_BASES_20X,PCT_TARGET_BASES_100X) %>%
      left_join(typeMap)

  caution=tibble(METRIC=colnames(hsm) %>% grep("_",.,value=T),CAUTION=c(100,0.02,.95,.50),FAIL=c(25,0.05,.80,.10))
  dh=hsm %>% gather(METRIC,VALUE,-SAMPLE,-TYPE) %>% left_join(typeMap) %>% group_split(.$R)

  plot_hsm<-function(dhi) {
      ggplot(dhi,aes(SAMPLE,VALUE,fill=TYPE)) + theme_light(10) + geom_col(alpha=.85) + facet_wrap(~METRIC,scale="free_y") + scale_x_discrete(guide = guide_axis(angle = 30)) + theme(plot.margin=unit(c(5,5,5,20),"mm")) + guides() + geom_hline(aes(yintercept=CAUTION),data=caution,color="gold4",linewidth=1) + geom_hline(aes(yintercept=FAIL),data=caution,color="darkred",linewidth=1.4) + scale_fill_jama()
  }

  phsm=map(dh,plot_hsm)

} else {
  phsm=NULL
}

rDir="post/reports"
fs::dir_create(rDir)

projNo <- basename(fs::dir_ls("out"))
if(!grepl("^Proj_",projNo)) projNo=cc("Proj",projNo)

rFile=cc(projNo,"qcRpt01.pdf")

pdf(file=file.path(rDir,rFile),width=11,height=8.5)
print(pg1)
print(pg2)
print(phsm)
dev.off()

facetsQCColsFile=file.path(SDIR,"rsrc","facetsQCCols")
facetsQCCols=scan(facetsQCColsFile,"")
facetsQCFiles=dir_ls(sampleDir,"\\.facets_qc\\.txt")
df=map(facetsQCFiles,read_tsv,col_types=cols(.default="c"),progress=F,.progress=T) %>%
    bind_rows %>%
    type_convert
flags=df %>%
    select(tumor_sample_id,matches("pass")) %>%
    gather(filter,value,matches("pass")) %>%
    filter(!value) %>%
    group_by(tumor_sample_id) %>%
    summarize(FailedFilters=paste(filter,collapse=";"))
dg=df %>%
    select(all_of(facetsQCCols)) %>%
    left_join(flags) %>%
    mutate(tumor_sample_id=gsub("__.*","",tumor_sample_id))

dg=dg %>%
    arrange(facets_qc,desc(purity))

dg %>%
    filter(!facets_qc) %>%
    pull(tumor_sample_id) %>%
    write("facetsFailedSamples")

rFile=cc(projNo,"facetsQCRpt_v1.xlsx")
openxlsx::write.xlsx(dg,file.path(rDir,rFile))

