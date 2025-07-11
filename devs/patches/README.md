# Feature Patches


## SV Caller updates

All of these patches can be applied by merging in the `update/sv-callers-01` branch in the soccin fork. 

### feature-upgrade_delly_v126

- 8bcbf291 (origin/feature/upgrade_delly_v126)
updated delly and htslib in delly-bcftools docker image [Anne Marie Noronha]

### update-svaba

- e6eedae0 (origin/update/svaba)
update svaba container with LABEL and add updated tag to config [Anne Marie Noronha]


## Neoantigen Speedups

- 50854c1e (enhancement/neoantigen_parallel)
resources_juno.config memory update [GitHub]


## NF-core updates/fixes

### update--nf-core_modules

Fixes disk space issues in some gatk modules. This does not include the changes to improve the tempo bam processing
