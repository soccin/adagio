require(tidyverse)
argv=commandArgs(trailing=T)
mafFiles=argv

maf=map(mafFiles,read_tsv,comment="#") %>%
    bind_rows %>%
    mutate(n_var_freq=n_alt_count/n_depth)


tbl1=maf %>%
    mutate(GPos=paste0(Chromosome,":",Start_Position,"-",End_Position)) %>%
    select(
        Sample=Matched_Norm_Sample_Barcode,Gene=Hugo_Symbol,Type=Variant_Classification,
        dbSNP_RS,Alteration=HGVSp_Short,
        VAF=n_var_freq,
        n_depth,n_alt_count,
        GPos,REF=Reference_Allele,ALT=Tumor_Seq_Allele2
    ) %>%
    arrange(Gene,Sample) %>%
    filter(!is.na(Alteration) | Gene=="TERT") %>%
    filter(!grepl("=$",Alteration))

class(tbl1$VAF)="percentage"

numMutations=tbl1 %>% count(Sample,name="NumMutations") %>% arrange(desc(NumMutations))
nSamples=distinct(tbl1,Sample) %>% nrow

library(openxlsx)
# set zoom
set_zoom <- function(sV,x) gsub('(?<=zoomScale=")[0-9]+', x, sV, perl = TRUE)

wb=createWorkbook()
styleHeader=createStyle(wrapText = TRUE, halign="left", textDecoration = c("bold"))

#
# Sheet 3 - MAF0
#

addWorksheet(wb,sheetName="Mutations")
writeDataTable(wb,sheet=1,tbl1,tableStyle="none",withFilter=F)
addStyle(wb,sheet=1,cols=1:ncol(tbl1),row=1,style=styleHeader,gridExpand=T)
wb$worksheets[[1]]$sheetViews=set_zoom(wb$worksheets[[1]]$sheetViews,120)
setColWidths(wb,sheet=1,cols=1:ncol(tbl1),widths="auto")
setColWidths(wb,sheet=1,cols=1,widths=12)
setColWidths(wb,sheet=1,cols=5:6,widths=14)

projNo=grep("^Proj",strsplit(getwd(),"/")[[1]],value=T)
if(len(projNo)==0) {
    projNo=""
}
rFile=cc(projNo,"ReportGermline","v2.xlsx")
rDir="post/reports"
fs::dir_create(rDir)

saveWorkbook(wb,file.path(rDir,rFile),overwrite=T)


