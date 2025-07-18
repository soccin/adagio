PROOT=get_script_dir()
source(file.path(PROOT,"rsrc/read_tempo_sv.R"))
argv=commandArgs(trailing=T)
require(tidyverse)

fof=fs::dir_ls("out",recur=T,regex="\\.final\\.clustered\\.bedpe$")
dd=map(fof,read_tempo_sv_somatic,.progress=T) %>% bind_rows

dd=dd %>% select(-INFO_A,-INFO_B,-FORMAT,-TUMOR,-NORMAL)

dd=dd %>% select(1:CC_Chr_Band,matches("_(AD|PE|SR|PR|PS)$"),matches("^CC|^DGv"),matches("CONSENSUS"),everything()) %>% type_convert

dd=dd %>%
    mutate(t_delly_SpanVAF=t_delly_DV/(t_delly_DV+t_delly_DR)) %>%
    mutate(t_delly_JuncVAF=t_delly_RV/(t_delly_RV+t_delly_RR)) %>%
    mutate(n_delly_SpanVAF=n_delly_DV/(n_delly_DV+n_delly_DR)) %>%
    mutate(n_delly_JuncVAF=n_delly_RV/(n_delly_RV+n_delly_RR)) %>%
    separate(t_manta_SR,c("t_manta_SRR","t_manta_SRV"),remove=F) %>%
    mutate(t_manta_JuncVAF=as.numeric(t_manta_SRV)/(as.numeric(t_manta_SRV)+as.numeric(t_manta_SRR))) %>%
    mutate(t_svaba_VAF=t_svaba_AD/t_svaba_DP) %>%
    mutate(n_svaba_VAF=n_svaba_AD/n_svaba_DP)

df=dd %>% select(1:CC_Chr_Band,matches("VAF"),matches("_(AD|PE|SR|PR|PS|DR|DV|RR|RV)$"),matches("^CC|^DGv"),matches("CONSENSUS"),NORMAL_ID,UUID)
colDesc=read_csv(file.path(PROOT,"rsrc/svColTypeDescriptions.csv"))

projNo=grep("^Proj",strsplit(getwd(),"/")[[1]],value=T)
if(len(projNo)==0) {
    projNo=""
}
rFile=cc(projNo,"SV_Report01","v4.xlsx")
rDir="post/reports"
fs::dir_create(rDir)

write_xlsx(
    list(SVEvents=df,ColDescriptions=colDesc),
    file.path(rDir,rFile)
)

