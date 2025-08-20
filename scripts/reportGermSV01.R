PROOT=get_script_dir()
source(file.path(PROOT,"rsrc/read_tempo_sv.R"))
argv=commandArgs(trailing=T)
suppressPackageStartupMessages({
  require(tidyverse)
  require(openxlsx)
})

fof=fs::dir_ls("out",recur=T,regex="germ.*\\.final\\.bedpe")
read_germline_sv<-function(tfile) {
  readr::read_tsv(tfile,comment="##",col_types=cols(.default="c"),progress=F) |> rename(CHROM_A=`#CHROM_A`) %>% select(NORMAL_ID,everything())
}

dd=map(fof,read_germline_sv) %>% bind_rows

cmdlog=fs::dir_ls("out",recur=2,regex="cmd.sh.log")

projNo=readLines(cmdlog) %>% grep("PROJECT_ID:",.,value=T) %>% strsplit(" ") %>% map_vec(2)

rFile=cc(projNo,"SVGermline_Report01","v4.xlsx")
rDir="germline/reports"
fs::dir_create(rDir)

write_xlsx(
    list(GermSVs=dd),
    file.path(rDir,rFile)
)

