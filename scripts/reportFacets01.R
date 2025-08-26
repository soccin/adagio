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

run_info=fs::dir_ls("out",recur=3,regex="cohort_level/.*/cna_facets_run_info.txt") %>% map_dfr(read_tsv) %>% filter(grepl("purity",Sample))
cna_armlevel=fs::dir_ls("out",recur=3,regex="cohort_level/.*/cna_armlevel.txt") %>% map_dfr(read_tsv) %>% filter(sample!="sample") %>% type_convert
cna_genelevel=fs::dir_ls("out",recur=3,regex="cohort_level/.*/cna_genelevel.txt") %>% map_dfr(read_tsv)

rfile=cc("Proj",projectNo,"CNV_Facets_v2.xlsx")

write_xlsx(list(
  runInfo=run_info,
  armLevel=cna_armlevel,
  geneLevel=cna_genelevel
  ),
  rfile
)
