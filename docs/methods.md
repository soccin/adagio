# Variant Calling Pipeline

### Version 2.3.7

## Overview

Sequence mapping and variant calling were done using the TEMPO pipeline [Tempo2024], which is an nf-core/nextflow-based pipeline [Garcia2020, Ewels2020]. The output was then post-processed using a custom R script to filter for non-silent mutations. This script, along with the code to run the pipeline and a link to the specific version of the TEMPO code that was used, is available at this link: [https://github.com/soccin/adagio/releases/tag/v2.3.7](https://github.com/soccin/adagio/releases/tag/v2.3.7).


## Details

Input sequence files (FASTQ) are aligned with `bwa` (*bwa mem*) and then sorted and merged with `samtools`. The resulting BAM files are then processed with GATK's MarkDuplicates and BaseRecalibrator tools. The BAM files are then grouped into tumor/normal pairs and run through the variant calling stage, which consists of GATK Mutect2 and Strelka2. Additionally, Manta is run, and candidate indels are passed to Strelka along with the BAM pairs. The resulting VCF files are then processed with `bcftools` to annotate the calls before the final VCF is converted to a MAF file with `vcf2maf`. This MAF file is then processed with a custom R script to generate a mutation report of non-silent mutations.


## References

Garcia M, Juhos S, Larsson M, et al. Sarek: A portable workflow for whole-genome sequencing analysis of germline and somatic variants. F1000Research 2020, 9:63 ([https://doi.org/10.12688/f1000research.16665.2](https://doi.org/10.12688/f1000research.16665.2))

Ewels, PA, Peltzer, A, Fillinger, S, et al. The nf-core framework for community-curated bioinformatics pipelines. Nat Biotechnol 38, 276–278 (2020). ([https://doi.org/10.1038/s41587-020-0439-x](https://doi.org/10.1038/s41587-020-0439-x))

Tempo2024, version 1.4.4 (commit: 0445c8e) [https://github.com/mskcc/tempo](https://github.com/mskcc/tempo)
