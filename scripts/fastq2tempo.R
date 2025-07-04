argv=commandArgs(trailing=T)

if(len(argv)<2) {
    cat("\n\tfastq2tempo.R R1_MAP.tsv BIC_PAIRING.txt [TARGET_MANIFEST.csv]\n\n")
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
    mutate(FASTQ_PE2=str_replace(FASTQ_PE1,"_R1_(\\d+).fastq---","_R2_\\1.fastq"))

if(any(!fs::file_exists(mapping$FASTQ_PE2))) {
    cat("\n\nERROR missing R2 files\n\n")
    rlang::abort("ERROR")
}

if(is.null(targetFile)) {

    mapping$TARGET="idt_v2"

} else {

    targets=read_csv(targetFile,col_names=c("SAMPLE","TARGET"))
    mapping=mapping %>% left_join(targets)

}

mapping=mapping %>% select(SAMPLE,TARGET,everything())

write_tsv(mapping,"inputTempo_mapping.tsv")

pairing=read_tsv(pairingFile,col_names=c("NORMAL_ID","TARGET_ID"))

write_tsv(pairing,"inputTempo_pairing.tsv")

