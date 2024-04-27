require(tidyverse)

mafFile=fs::dir_ls("out",recurs=2,regex="cohort_level") %>% fs::dir_ls(regex="mut_somatic.maf")

maf=read_tsv(mafFile,comment="#")

tbl1=maf %>%
    select(
        Sample=Tumor_Sample_Barcode,Gene=Hugo_Symbol,Type=Variant_Classification,
        dbSNP_RS,Alteration=HGVSp_Short,oncogenic,
        VAF=t_var_freq,t_depth,t_alt_count,
        n_depth,n_alt_count,
        Matched_Norm_Sample_Barcode) %>%
    filter(!is.na(Alteration) & !grepl("=$",Alteration)) %>%
    arrange(Gene,Sample)

class(tbl1$VAF)="percentage"
library(openxlsx)
wb=createWorkbook()
addWorksheet(wb,sheetName="NonSilentEvents")
writeDataTable(wb,sheet=1,tbl1,tableStyle="none",withFilter=F)
setColWidths(wb,sheet=1,cols=1:ncol(tbl1),widths="auto")
setColWidths(wb,sheet=1,cols=5:6,widths=20)
projNo=grep("^Proj",strsplit(getwd(),"/")[[1]],value=T)
if(len(projNo)==0) {
    projNo=""
}

rFile=cc(projNo,"mutationReport","v1.xlsx")
rDir="post/reports"
fs::dir_create(rDir)

saveWorkbook(wb,file.path(rDir,rFile),overwrite=T)
