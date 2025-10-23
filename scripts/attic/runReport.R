argv=commandArgs(trailing=TRUE)
if(len(argv)==0) {
  cat("
  usage: runReport.R nf_tracefile_01.txt [nf_tracefile_02 ...]\n\n")
  quit()
}

SDIR=get_script_dir()
RSRC="rsrc/nf-reports"

require(tidyverse)

# Source the function modules
source(file.path(SDIR,RSRC,"trace_parser.R"))
source(file.path(SDIR,RSRC,"nextflow_analysis.R"))
source(file.path(SDIR,RSRC,"status_reports.R"))

report=generate_status_report(argv)

projNo=grep("^Proj",strsplit(getwd(),"/")[[1]],value=T)
if(len(projNo)==0) {
    projNo=""
}
rFile=cc(projNo,"runReport",DATE(),".xlsx")
write_xlsx(report,rFile)
write_csv(report$failure_report,cc(projNo,"FailedSamples",DATE(),".csv"))
