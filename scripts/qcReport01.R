require(tidyverse)
require(ggsci)

projectNo=basename(fs::dir_ls("out"))
cohortDir=file.path("out",projectNo,"cohort_level")
sampleDir=file.path("out",projectNo,"somatic")

x11 = function (...) grDevices::x11(...,type='cairo')

getSDIR <- function(){
    args=commandArgs(trailing=F)
    TAG="--file="
    path_idx=grep(TAG,args)
    SDIR=fs::path_real(dirname(substr(args[path_idx],nchar(TAG)+1,nchar(args[path_idx]))))
    if(length(SDIR)==0) {
        return(fs::path_real(Sys.getenv("SDIR")))
    } else {
        return(SDIR)
    }
}

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

pdf(file=cc("Proj",projectNo,"qcRpt01.pdf"),width=11,height=8.5)
print(pg1)
print(pg2)
dev.off()

facetsQCColsFile=file.path(getSDIR(),"rsrc","facetsQCCols")
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

dg=dg %>% arrange(facets_qc,desc(purity))

dg %>% filter(!facets_qc) %>% pull(tumor_sample_id) %>% write("facetsFailedSamples")
openxlsx::write.xlsx(dg,cc("Proj",projectNo,"facetsRpt.xlsx"))

