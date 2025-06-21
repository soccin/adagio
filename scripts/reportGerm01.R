require(tidyverse)

maffile=fs::dir_ls("out",recur=3,regex="mut_germline.maf")
qcfile=fs::dir_ls("out",recur=3,regex="alignment_qc.txt")
cmdlog=fs::dir_ls("out",recur=2,regex="cmd.sh.log")


if(len(maffile)<1) {
    cat("\n\nFATAL ERROR: Can not find any Germline MAFs\n\n")
    rlang::abort("ERROR")
}

#
# Get normal samples
#

normals=readLines(cmdlog) %>%
    grep("Script:",.,value=T) %>%
    strsplit(" ") %>%
    map_vec(5) %>%
    read_tsv(show_col_types = FALSE,progress=T) %>%
    pull(NORMAL_ID)

projectId=readLines(cmdlog) %>%
    grep("Script:",.,value=T) %>%
    strsplit(" ") %>%
    map_vec(3) %>%
    readLines %>%
    grep("requestId:",.,value=T) %>%
    strsplit(" ") %>%
    map_vec(2) %>%
    gsub('"','',.)

#
# QC/Table
#
qcTbl=read_tsv(qcfile) %>%
    filter(Sample %in% normals)

maf=read_tsv(maffile) %>%
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
    arrange(Gene,GPos,Sample) %>%
    filter(!is.na(Alteration) | Gene=="TERT") %>%
    filter(!grepl("=$",Alteration))

class(tbl1$VAF)="percentage"

totalMuts=maf %>%
    count(Matched_Norm_Sample_Barcode) %>%
    select(Sample=Matched_Norm_Sample_Barcode,TotalMutations=n)

numMutations=tbl1 %>%
    count(Sample,name="NumNonSilentMutations")

tbl0=left_join(qcTbl,totalMuts) %>%
    left_join(numMutations) %>%
    select(Sample,TotalMutations,NumNonSilentMutations,MeanTargetCoverage,FractionTargets20X,FractionTargetsZeroCoverage,FractionDuplicateMarked,TotalReads)
class(tbl0$FractionTargets20X)="percentage"
class(tbl0$FractionTargetsZeroCoverage)="percentage"
class(tbl0$FractionDuplicateMarked)="percentage"

library(openxlsx)
# set zoom
set_zoom <- function(sV,x) gsub('(?<=zoomScale=")[0-9]+', x, sV, perl = TRUE)

wb=createWorkbook()
styleHeader=createStyle(wrapText = TRUE, halign="left", textDecoration = c("bold"))
sheet=1

addWorksheet(wb,sheetName="Samples")
writeDataTable(wb,sheet=sheet,tbl0,tableStyle="none",withFilter=F)
addStyle(wb,sheet=sheet,cols=1:ncol(tbl0),row=1,style=styleHeader,gridExpand=T)
wb$worksheets[[sheet]]$sheetViews=set_zoom(wb$worksheets[[sheet]]$sheetViews,120)
setColWidths(wb,sheet=sheet,cols=1:ncol(tbl0),widths="auto")

#
# NonSilent Mutations
#
sheet=sheet+1
addWorksheet(wb,sheetName="NonSilent")
writeDataTable(wb,sheet=sheet,tbl1,tableStyle="none",withFilter=F)
addStyle(wb,sheet=sheet,cols=1:ncol(tbl1),row=1,style=styleHeader,gridExpand=T)
wb$worksheets[[sheet]]$sheetViews=set_zoom(wb$worksheets[[sheet]]$sheetViews,120)
setColWidths(wb,sheet=sheet,cols=1:ncol(tbl1),widths="auto")
setColWidths(wb,sheet=sheet,cols=5,widths=20) # Alteration Column
setColWidths(wb,sheet=sheet,cols=10:11,widths=20) # Alteration Column
#setColWidths(wb,sheet=sheet,cols=5:6,widths=14)

projNo=grep("^Proj",strsplit(getwd(),"/")[[1]],value=T)
if(len(projNo)==0) {
    projNo=""
}

rFile=cc(projNo,"ReportGermline","v2.xlsx")
rDir="post/reports"
fs::dir_create(rDir)

saveWorkbook(wb,file.path(rDir,rFile),overwrite=T)


