require(tidyverse)
facetsReport=fs::dir_ls(regex="facetsRpt.xlsx")
if(len(facetsReport)==1) {
    fqc=readxl::read_xlsx(facetsReport)
    failedSamples=fqc %>% filter(!facets_qc) %>% pull(tumor_sample_id)
} else {
    failedSamples=""
}

projectNo=basename(fs::dir_ls("out"))

seg=fs::dir_ls("out",recur=T,regex="default_cohort/cna_purity_run_segmentation.seg") %>%
    read_tsv %>%
    mutate(ID=gsub("__.*","",ID)) %>%
    filter(!(ID %in% failedSamples))

write_tsv(seg,cc("Proj",projectNo,"facets_purity.seg"))

seg=fs::dir_ls("out",recur=T,regex="default_cohort/cna_hisens_run_segmentation.seg") %>%
    read_tsv %>%
    mutate(ID=gsub("__.*","",ID)) %>%
    filter(!(ID %in% failedSamples))

write_tsv(seg,cc("Proj",projectNo,"facets_hisens.seg"))
