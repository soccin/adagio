argv=commandArgs(trailing=T)
sampleIdRegEx=argv[1]
seqFiles=scan(argv[2],"")

mapping=list()
for(si in seqFiles) {
    f12=strsplit(si,",")[[1]]
    sid=stringr::str_extract(f12[1],sampleIdRegEx,group=T)
    mapping[[len(mapping)+1]]=tibble::tibble(
                                    SAMPLE=sid,TARGET="wgs",
                                    FASTQ_PE1=fs::path_real(f12[1]),
                                    FASTQ_PE2=fs::path_real(f12[2])
                                )
}

readr::write_tsv(dplyr::bind_rows(mapping),"mapping_fastq_tempo.tsv")

