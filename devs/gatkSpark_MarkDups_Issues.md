# Gatk SPARK MarkDups

## Increased memory consumption by MarkDuplicatesSpark #8307

https://github.com/broadinstitute/gatk/issues/8307

Resolution:

Thanks for the helpful suggestions. Indeed, seems that adding just these --conf parameters: --conf spark.driver.memory=6g  --conf spark.executor.memory=5g solved it!
Thanks for the help. For the others - this is the command that I ended up running


```
java -Xmx190g -jar ~{gitc_path}GATK_ultima.jar MarkDuplicatesSpark \
  --spark-master local[24] \
  --conf spark.driver.memory=6g \
  --conf spark.executor.memory=5g \
  --spark-verbosity WARN \
  --input ~{sep=" --input " input_bams} \
  --output ~{output_bam_basename}.bam \
  --create-output-bam-index true \
  --verbosity WARNING \
```
