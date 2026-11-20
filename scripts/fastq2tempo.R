argv=commandArgs(trailing=T)

if(len(argv)<2) {
    cat("
    usage: fastq2tempo.R R1_MAP.tsv BIC_PAIRING.txt [TARGET_MANIFEST.csv]

    All input files have NO header line.

    R1_MAP.tsv (tab-separated): SAMPLE, path to R1 FASTQ
      One line per R1 file (a sample may have several). R1 files must
      match *_R1_NNN.fastq*; the R2 path is derived by R1 -> R2 and
      must exist.

        s_T01    /path/to/s_T01_L001_R1_001.fastq.gz
        s_T01    /path/to/s_T01_L002_R1_001.fastq.gz
        s_N01    /path/to/s_N01_L001_R1_001.fastq.gz

    BIC_PAIRING.txt (tab-separated): NORMAL, TUMOR

        s_N01    s_T01

    TARGET_MANIFEST.csv (comma-separated, optional): SAMPLE,TARGET
      If omitted, all samples get TARGET=idt_v2.

        s_T01,idt_v2
        s_N01,idt_v2

    Writes inputTempo_mapping.tsv and inputTempo_pairing.tsv to the
    current directory.

")
    quit()
}

r1mapFile=argv[1]
pairingFile=argv[2]

if(len(argv)>=3) {
    targetFile=argv[3]
} else {
    targetFile=NULL
}

require(tidyverse)

mapping=read_tsv(r1mapFile,col_names=F) %>%
    rename(SAMPLE=X1,FASTQ_PE1=X2) %>%
    mutate(FASTQ_PE1=fs::path_real(FASTQ_PE1)) %>%
    mutate(FASTQ_PE2=str_replace(FASTQ_PE1,"_R1_(\\d+).fastq","_R2_\\1.fastq"))

#
# An R1 name without _R1_NNN.fastq is left unchanged by the R2
# substitution, so the R1 file would also be used as R2
#
badR1=mapping |> filter(!str_detect(basename(FASTQ_PE1),"_R1_\\d+\\.fastq"))
if(nrow(badR1)>0) {
    cat("\n\nERROR R1 files that do not match *_R1_NNN.fastq*:\n\n")
    cat(str_glue("    {badR1$SAMPLE}  {badR1$FASTQ_PE1}"),sep="\n")
    cat("\n")
    rlang::abort("ERROR")
}

if(any(!fs::file_exists(mapping$FASTQ_PE2))) {
    cat("\n\nERROR missing R2 files\n\n")
    rlang::abort("ERROR")
}

if(is.null(targetFile)) {

    mapping$TARGET="idt_v2"

} else {

    targets=read_csv(targetFile,col_names=c("SAMPLE","TARGET"))
    mapping=mapping %>% left_join(targets)

    noTarget=mapping |> filter(is.na(TARGET)) |> distinct(SAMPLE) |> pull(SAMPLE)
    if(len(noTarget)>0) {
        cat("\n\nERROR samples missing from the target manifest",targetFile,"\n\n")
        cat(str_c("    ",noTarget),sep="\n")
        cat("\n")
        rlang::abort("ERROR")
    }

}

mapping=mapping %>% select(SAMPLE,TARGET,everything())

pairing=read_tsv(pairingFile,col_names=c("NORMAL_ID","TUMOR_ID"))

#
# A pair with a sample that is not in the mapping would be dropped by
# Tempo with no message, so stop here and name it
#
droppedPairs=pairing |>
    filter(!(NORMAL_ID %in% mapping$SAMPLE & TUMOR_ID %in% mapping$SAMPLE))
if(nrow(droppedPairs)>0) {
    cat("\n\nERROR pairs with a sample that is not in",r1mapFile,"\n\n")
    cat(str_glue("    NORMAL={droppedPairs$NORMAL_ID}  TUMOR={droppedPairs$TUMOR_ID}"),sep="\n")
    cat("\n")
    rlang::abort("ERROR")
}

write_tsv(mapping,"inputTempo_mapping.tsv")
write_tsv(pairing,"inputTempo_pairing.tsv")

