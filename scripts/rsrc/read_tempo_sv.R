suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tidyr)
})

# infoAFlds=c("Callers", "NumCallers", "NumCallersPass", "STRANDS",
# "brass_PS", "brass_RC",
# "delly_PE", "delly_SR",
# "manta_PR", "manta_SR", "svaba_DR", "svaba_SR", "svaba_DP")

read_tempo_sv_somatic<-function(tfile) {

    tt=readr::read_tsv(tfile,comment="##",col_types=cols(.default="c"),progress=F) |>
        rename(CHROM_A=`#CHROM_A`) |>
        mutate(UUID=cc(TUMOR_ID,ID)) |>
        select(CHROM_A:END_B,TYPE,UUID,everything())

    if(nrow(tt)==0) return(NULL)

    infoA=tt %>%
        select(UUID,INFO_A) %>%
        separate_rows(INFO_A,sep=";") %>%
        separate(INFO_A,c("Key","Val"),sep="=",fill="right") %>%
        spread(Key,Val)

    formats=tt %>%
        select(UUID,FORMAT) %>%
        separate_rows(FORMAT,sep=":") %>%
        mutate(RID=row_number())

    tumors=tt %>%
        select(UUID,TUMOR) %>%
        separate_rows(TUMOR,sep=":") %>%
        mutate(RID=row_number())

    tumorFmt=full_join(formats,tumors,by = join_by(UUID, RID)) %>%
        select(-RID) %>%
        mutate(FORMAT=paste0("t_",FORMAT)) %>%
        spread(FORMAT,TUMOR)

    normals=tt %>%
        select(UUID,NORMAL) %>%
        separate_rows(NORMAL,sep=":") %>%
        mutate(RID=row_number())

    normalFmt=full_join(formats,normals,by = join_by(UUID, RID)) %>%
        select(-RID) %>%
        mutate(FORMAT=paste0("n_",FORMAT)) %>%
        spread(FORMAT,NORMAL)



    # if("manta_PR" %in% colnames(tumorFmt)) {
    #     tumorFmt=tumorFmt %>%
    #         separate(manta_PR,c("manta_PR_REF","manta_PR_ALT"),sep=",")
    # }

    # if("manta_SR" %in% colnames(tumorFmt)) {
    #     tumorFmt=tumorFmt %>%
    #         separate(manta_SR,c("manta_SR_REF","manta_SR_ALT"),sep=",")
    # }

    tt=tt %>%
        rename(repeat.site1=`repName-repClass-repFamily:-site1`) %>%
        rename(repeat.site2=`repName-repClass-repFamily:-site2`)

    priorityCols=scan(file.path(PROOT,"rsrc/reportCols01"),"",quiet=T)

    left_join(tt,infoA,by="UUID") %>%
        left_join(tumorFmt,by="UUID") %>%
        left_join(normalFmt,by="UUID") %>%
        select(all_of(priorityCols),everything())

}