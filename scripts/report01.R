suppressPackageStartupMessages(require(tidyverse))

argv=commandArgs(trailingOnly=TRUE)
ASSAY=argv[1]
if(is.na(ASSAY)) { ASSAY="UNKNOWN" }

SDIR=get_script_dir()
source(file.path(SDIR,"get_cluster_name.R"))
CLUSTER=get_cluster_name()
cat("CLUSTER =",CLUSTER,"\n\n")

#
# Get Facets QC info
#

facetsQCFiles=fs::dir_ls("out",recurs=3,regex="somatic.*facets") %>% fs::dir_ls(recur=1,regex=".facets_qc.txt")

facetsDat=map(facetsQCFiles,read_tsv,show_col_types = FALSE,progress=F,col_types=cols(.default="c")) %>%
    bind_rows %>%
    quietly(type_convert)(.) %>% pluck("result") %>%
    select(tumor_sample_id,facets_qc,purity=purity_run_Purity,ploidy,fga) %>%
    separate(tumor_sample_id,c("SampleID","NormalID"),sep="__")

#
# If facets failed then set values to NA
#
# facetsDat$purity[!facetsDat$facets_qc]=NA
facetsDat$ploidy[!facetsDat$facets_qc]=NA
facetsDat$fga[!facetsDat$facets_qc]=NA
#facetsDat$wgd[!facetsDat$facets_qc]=NA

#
# Get Sample level info
#

sampleDataFile=fs::dir_ls("out",recur=2,regex="cohort_level/default_cohort") %>% fs::dir_ls(regex="sample_data.txt")

if(len(sampleDataFile)==0) {
    cat("\n\tERROR: can not find [sample_data.txt] in output folder\n\n")
    rlang::abort("FATAL::ERROR")
}

sampleData=read_tsv(sampleDataFile,show_col_types=FALSE,progress=F) %>%
    separate(sample,c("Sample","NormalID"),sep="__") %>%
    select(-matches("^SB|^HLA|^MSI")) %>%
    select(SampleID=Sample,NormalID,`Mutation Count`=Number_of_Mutations,TMB) %>%
    left_join(facetsDat,by = join_by(SampleID, NormalID)) %>%
    select(-facets_qc,facets_qc) %>%
    rename(`Facets Purity`=purity,`Facets Ploidy`=ploidy,`Fraction Genome Altered`=fga)

if(!(ASSAY=="WES" || ASSAY=="exome")) {
    sampleData=sampleData %>% select(-TMB)
}

mafFile=fs::dir_ls("out",recurs=2,regex="cohort_level") %>% fs::dir_ls(regex="mut_somatic.maf")

#maf=read_tsv(mafFile,comment="#",show_col_types=FALSE,progress=F,col_types=cols(.default=""))
#
# read_tsv is very fussy about something I am not sure
# complains about missing columns but nothing appears
# to be missing.
#
maf <- data.table::fread(mafFile, skip = "Hugo_Symbol", sep = "\t", na.strings = c("", "NA")) %>% tibble

switch(CLUSTER,
    "JUNO"={
        portalWESGeneFreqFile="/juno/bic/work/socci/Work/Resources/Portal/2024-08-09/msk-wes_MutatedGenes_2024-08-09.txt"
    },
    "IRIS"={
        portalWESGeneFreqFile="/home/soccin/Work/Resources/Portal/2024-08-09/msk-wes_MutatedGenes_2024-08-09.txt"
    },
    {
        cat("\n\nUnknown CLUSTER",CLUSTER,"\n\n")
        rlang::abort("FATAL ERROR")
    }
)

af_MSK_WES=read_tsv(portalWESGeneFreqFile,show_col_types=FALSE,progress=F) %>% mutate(AF=`#`/`Profiled Samples`) %>% select(Gene,AF)

extraCols=c("non_cancer_AF_popmax","SIFT","PolyPhen","IMPACT")
extraCols=intersect(extraCols,colnames(maf))

tbl1=maf %>%
    mutate(GPos=paste0(Chromosome,":",Start_Position,"-",End_Position)) %>%
    select(
        Sample=Tumor_Sample_Barcode,Gene=Hugo_Symbol,Type=Variant_Classification,
        dbSNP_RS,Alteration=HGVSp_Short,oncogenic,
        VAF=t_var_freq,t_depth,t_alt_count,
        n_depth,n_alt_count,
        Normal_Sample=Matched_Norm_Sample_Barcode,
        GPos,REF=Reference_Allele,ALT=Tumor_Seq_Allele2,
        all_of(extraCols)
    ) %>%
    rename(VEP_IMPACT=IMPACT) %>%
    filter(!is.na(Alteration) & !grepl("=$",Alteration)) %>%
    arrange(Gene,Sample) %>%
    left_join(af_MSK_WES,by = join_by(Gene)) %>%
    rename(MSKWES_GENE_Frac=AF)


class(tbl1$VAF)="percentage"
class(tbl1$MSKWES_GENE_Frac)="percentage"

numMutations=tbl1 %>% count(Sample,name="NumMutations") %>% arrange(desc(NumMutations))
nSamples=distinct(tbl1,Sample) %>% nrow

mutatedGenes=tbl1 %>%
    distinct(Sample,Gene) %>%
    group_by(Gene) %>%
    summarize(Count=n(),Samples=paste0(sort(Sample),collapse=",")) %>%
    mutate(Freq=Count/nSamples) %>%
    arrange(desc(Freq),Gene) %>%
    select(Gene,Count,Freq,Samples) %>%
    filter(Count>1)

class(mutatedGenes$Freq)="percentage"

nonSymCount=tbl1 %>% count(Sample) %>% rename(SampleID=Sample,`NonSyn Mutation Count`=n)
sampleData=sampleData %>% left_join(nonSymCount,by = join_by(SampleID))

library(openxlsx)
# set zoom
set_zoom <- function(sV,x) gsub('(?<=zoomScale=")[0-9]+', x, sV, perl = TRUE)

wb=createWorkbook()

rows=2:(nrow(sampleData)+1)

#
# Sheet 1 - Sample Data
#
addWorksheet(wb,sheetName="Sample Data")
writeDataTable(wb,sheet=1,sampleData,tableStyle="none",withFilter=F)

styleHeader=createStyle(wrapText = TRUE, halign="left", textDecoration = c("bold"))
addStyle(wb,sheet=1,cols=1:ncol(sampleData),row=1,style=styleHeader,gridExpand=T)

addStyle(wb,sheet=1,cols=4,rows=rows,style=createStyle(numFmt="0.00"))
addStyle(wb,sheet=1,cols=5,rows=rows,style=createStyle(numFmt="0.00"))
addStyle(wb,sheet=1,cols=6,rows=rows,style=createStyle(numFmt="0.00"))
addStyle(wb,sheet=1,cols=7,rows=rows,style=createStyle(numFmt="0.00"))

setColWidths(wb,sheet=1,cols=1:ncol(sampleData),widths="auto")
setColWidths(wb,sheet=1,cols=1,widths=14)
setColWidths(wb,sheet=1,cols=3:7,widths=8)

wb$worksheets[[1]]$sheetViews=set_zoom(wb$worksheets[[1]]$sheetViews,120)

#
# Sheet 2 - Gene Stats
#
addWorksheet(wb,sheetName="Gene Stats")
writeDataTable(wb,sheet=2,mutatedGenes,tableStyle="none",withFilter=F)
rows=2:(nrow(mutatedGenes)+1)

addStyle(wb,sheet=2,cols=1:ncol(mutatedGenes),row=1,style=styleHeader,gridExpand=T)

wb$worksheets[[2]]$sheetViews=set_zoom(wb$worksheets[[2]]$sheetViews,120)
setColWidths(wb,sheet=2,cols=1:ncol(mutatedGenes),widths="auto")
setColWidths(wb,sheet=2,cols=3,widths=6.5)

#
# Sheet 3 - MAF0
#

addWorksheet(wb,sheetName="Mutations")
writeDataTable(wb,sheet=3,tbl1,tableStyle="none",withFilter=F)
addStyle(wb,sheet=3,cols=1:ncol(tbl1),row=1,style=styleHeader,gridExpand=T)
wb$worksheets[[3]]$sheetViews=set_zoom(wb$worksheets[[3]]$sheetViews,120)
setColWidths(wb,sheet=3,cols=1:ncol(tbl1),widths="auto")
setColWidths(wb,sheet=3,cols=1,widths=12)
setColWidths(wb,sheet=3,cols=5:6,widths=14)

projNo <- fs::dir_ls("out") %>% grep("/metrics",.,invert=T,value=T) %>% basename
if(!grepl("^Proj_",projNo)) {
  projNo=cc("Proj",projNo)
}
rFile=cc(projNo,"SNV_Report01","v2.xlsx")
rDir="post/reports"
fs::dir_create(rDir)

saveWorkbook(wb,file.path(rDir,rFile),overwrite=T)


