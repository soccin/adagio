getSDIR<-function() {
    ai=grep("--file=",commandArgs(),value=T)
    sdir=dirname(stringr::str_extract(ai,"=(.*)",group=T))

    if(len(sdir)==0) {
        sdir=Sys.getenv("SDIR")
        if(sdir=="") {
            cat("\n  Need to set SDIR\n\n")
            quit()
        }
    }

    sdir

}

SDIR=getSDIR()

argv=commandArgs(trailing=T)
if(len(argv)<1) {
    cat("\n\tusage: multiSVReport.R SV_SOMATIC.bedpe\n\n")
    quit()
}
require(tidyverse)

SVFILES=argv
vcf=map(SVFILES,read_tsv,comment="##",col_types=cols(.default="c")) %>% bind_rows %>% type_convert

infoParse=vcf %>%
    select(TUMOR_ID,NORMAL_ID,NAME_A,INFO_A) %>%
    separate_rows(INFO_A,sep=";") %>%
    filter(grepl("Call|SVTYPE|SVLEN",INFO_A)) %>%
    separate(INFO_A,c("KEY","VAL"),sep="=") %>%
    spread(KEY,VAL)

tbl1=left_join(vcf,infoParse) %>%
    rename(CHROM_A=`#CHROM_A`) %>%
    select(-INFO_A,-FORMAT,-TUMOR,-NORMAL,-NAME_A,-NAME_B) %>%
    select(TUMOR_ID,NORMAL_ID,Callers,NumCallers,NumCallersPass,SVTYPE,everything()) %>%
    arrange(desc(NumCallers),desc(NumCallersPass),TUMOR_ID) %>%
    type_convert

projectNo=gsub("Proj_","",grep("^Proj",strsplit(getwd(),"/")[[1]],value=T))
if(len(projectNo)==0) {
    projectNo=strsplit(getwd(),"/")[[1]]
    projectNo=projectNo[len(projectNo)]
}

headers=grep("^##(INFO)",readLines(SVFILES[1]),value=T)

infoTbl=list()
for(hi in headers) {
    column=str_extract(hi,"ID=(.*?),",group=T)
    description=str_extract(hi,"Description=\"(.*)\"",group=T)
    if(column %in% colnames(tbl1)) {
        infoTbl[[len(infoTbl)+1]]=tibble(Column=column,Description=description)
    }
}

docs=readLines(file.path(SDIR,"iAnnoteSVColumns.txt"))
for(di in docs) {
    dis=strsplit(di," : ")[[1]]
    column=dis[1]
    description=dis[2] %>% gsub(",$","",.)
    if(column %in% colnames(tbl1)) {
        infoTbl[[len(infoTbl)+1]]=tibble(Column=column,Description=description)
    }
}

infoTbl=bind_rows(infoTbl)

fusionFreq=tbl1 %>%
    select(TUMOR_ID,SVTYPE,matches("gene")) %>%
    mutate(Event=paste0(SVTYPE,"-",gene1,"::",gene2)) %>%
    select(TUMOR_ID,Event) %>%
    distinct %>%
    group_by(Event) %>%
    summarize(N=n(),Samples=paste0(TUMOR_ID,collapse=";")) %>%
    arrange(desc(N)) %>%
    filter(N>1)

geneFreq=tbl1 %>%
    select(TUMOR_ID,SVTYPE,matches("gene")) %>%
    gather(END,GENE,gene1,gene2) %>%
    select(TUMOR_ID,GENE) %>%
    distinct %>%
    group_by(GENE) %>%
    summarize(N=n(),Samples=paste0(TUMOR_ID,collapse=";")) %>%
    arrange(desc(N)) %>%
    filter(N>1)

openxlsx::write.xlsx(
    list(
        Fusions=fusionFreq,
        Genes=geneFreq,
        SVTable=tbl1,
        Glossary=infoTbl
    ),
    cc("proj",projectNo,"tempoSVCalls.xlsx")
)
