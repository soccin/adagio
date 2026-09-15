suppressPackageStartupMessages(require(tidyverse))
fields=c("Run_Pipeline", "Pipelines", "Institution", "RunNumber", "ProjectID",
"Species", "PI", "PI_Name", "PI_E-mail", "Investigator_E-mail",
"Investigator", "Investigator_Name", "ProjectFolder")

fields=paste0(fields,":")

readmeFile=c("README.txt", fs::path("..", "README.txt")) |>
    keep(fs::file_exists) |>
    head(1)
if(len(readmeFile)==0) {
    cat("\n\nCan not find README.txt in current or parent folder\n\n")
    quit(status=1)
}

cat(str_glue("Processing {readmeFile} ...\n\n"))

readme=grep("name:|email:|PI:|ID:|Species:|^IGO Project ID",readLines(readmeFile),value=T)
readme=tibble(Dat=readme) %>% separate(Dat,c("Key","Val"),sep=": ") %>% transpose
names(readme)=unlist(map(readme,"Key"))

RESULTS_ROOT="/data1/core002/res/bic/results"

labhead=tolower(gsub("@.*$","",readme[["Lab head / PI email"]]$Val))
invest=tolower(gsub("@.*$","",readme[["Your email"]]$Val))
projectNo=grep("^Proj",strsplit(getwd(),"/")[[1]],value=T)
if(len(projectNo)==0) {
    cat("\n\nCan not find project number from path\n\n")
    quit()
}

pipeline="UNKNOWN"
if(any(grepl("cellranger|analysis",fs::dir_ls()))){
    pipeline="seurat"
}

argv=commandArgs(trailing=T)
if(len(argv)>=1) {
  pipeline=argv[1]
  cat("\nSetting pipeline to:",pipeline,"\n\n")
}

runfolder="r_001"
if(len(argv)>=2) {
  runfolder=argv[2]
  cat("\nSetting runfolder to:",runfolder,"\n\n")
}

project=list(
    root=file.path(RESULTS_ROOT,labhead,invest,projectNo),
    runfolder=runfolder,
    project=gsub("^Proj_","",projectNo),
    pi=labhead,
    invest=invest,
    genome=tolower(readme$Species$Val),
    pipeline=pipeline
)

yaml::write_yaml(project,"project.yaml")
cat(yaml::as.yaml(project))

cat("\nDone.\n")