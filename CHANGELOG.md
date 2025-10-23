# Changelog

## v3-rc3 [2025-10-23] - Nextflow Trace Reporting and SLURM Integration

### Added
- **Nextflow Trace Report Generation**: New comprehensive trace file analysis [`becc945`, `cb6d303`]
  - Added `scripts/nfTraceReport.R` for analyzing and reporting on Nextflow trace files
  - Generates Excel report with two sheets:
    - Summary: Status counts for processes with failures (marked WARN if some completed, ERROR if none)
    - FAILED: Detailed records of all failed process instances
  - Output saved to `nfTraceReport_v1.xlsx` for pipeline failure analysis
  - Includes examples of trace analysis workflows: status summaries, failure reports, and SLURM status integration

- **SLURM Job Configuration**: Enhanced SLURM support for cluster execution [`43356f5`]
  - Added SLURM batch directives to `bin/runTempoWESCohort.sh` and `bin/runTempoWGSBam.sh`
  - Configured job name, output log paths, and CPU allocation (4 cores)
  - Set 7-day runtime limit
  - Partition settings (cmobic_cpu, cmobic_pipeline)
  - Scripts can now be submitted directly via sbatch

### Changed
- **Trace Parser Improvements**: Enhanced trace data handling [`becc945`, `cb6d303`]
  - Updated `scripts/rsrc/nf-reports/trace_parser.R` to handle status as ordered factor (COMPLETED, CACHED, FAILED, ABORTED) for proper sorting
  - Improved percentage column conversion with safe handling and warning suppression
  - Enhanced timestamp parsing with lubridate for complete timestamp handling
  - Sort trace files before processing in `process_multiple_traces()` for consistent ordering

- **Trace Report Refinement**: Streamlined analysis workflow [`f6ac869`]
  - Simplified `scripts/nfTraceReport.R` to focus on failure analysis
  - Removed debug halt and example code for cleaner production use
  - Improved report generation with focused failure tracking

### Fixed
- **SLURM Script Directory Handling**: Resolved path issues with sbatch [`b2e0f7f`]
  - Added logic to preserve script directory location when running under SLURM's sbatch
  - When sbatch runs a script, it copies to temporary folder, breaking relative paths
  - Fix checks for `SBATCH_SCRIPT_DIR` environment variable set by custom sbatch wrapper
  - Falls back to standard directory resolution method
  - Affected scripts: `bin/runTempoWESCohort.sh`, `bin/runTempoWGSBam.sh`

### Removed
- **Script Archival**: Cleanup of obsolete reporting scripts [`750852c`]
  - Moved `scripts/runReport.R` to `scripts/attic/` as no longer used in current pipeline workflow

### Technical Details
- **Branch Integration**: Merged multiple feature branches [`e92fe04`, `83cc477`, `619928a`]
  - Merged feat/nf-reports branch
  - Merged devs/iris branch
- **Files Modified**: 7 files with 89 insertions and 4 deletions
  - bin/runTempoWESCohort.sh (20 insertions, 1 deletion)
  - bin/runTempoWGSBam.sh (20 insertions, 1 deletion)
  - scripts/nfTraceReport.R (44 insertions, new file)
  - scripts/rsrc/nf-reports/trace_parser.R (7 insertions, 1 deletion)
  - scripts/rsrc/nf-reports/nextflow_analysis.R (2 insertions, 1 deletion)
  - scripts/runReport.R (renamed to scripts/attic/runReport.R)
- **Report Improvements**: New Nextflow trace reporting, SLURM integration, script cleanup
- **Infrastructure**: Enhanced cluster job submission capabilities

### Commit Summary
- **Total Commits**: 11 commits since v3-rc2 (5 non-merge commits)
- **Major Features**: Nextflow trace reporting, SLURM job configuration, path handling fixes
- **Script Updates**: Trace analysis, SLURM headers, directory resolution
- **Code Cleanup**: Archived obsolete scripts, streamlined reporting workflow

---

## v3-rc2 [2025-10-19] - Report Enhancements and WGS Support

### Added
- **TERT Mutation Reporting**: New dedicated TERT gene mutation report [`2015936`]
  - Added `scripts/reportTERT.R` for extracting TERT gene mutations from somatic MAF files
  - TERT mutations are important cancer biomarkers for telomerase reactivation
  - Filters for TERT gene mutations and selects relevant annotation columns
  - Outputs to Excel file: `Proj_<projNo>_TERT_Muts_v1.xlsx`

- **Non-Synonymous Mutation Counts**: Enhanced sample QC metrics [`9041c57`]
  - Added non-synonymous mutation count column to sample data output in `scripts/report01.R`
  - Provides important QC metric showing total non-synonymous mutations per sample
  - Integrated with existing sample data reporting

- **Verbose Post-Processing Logging**: Improved pipeline visibility [`0cee940`]
  - Added echo statements to `bin/doPost.sh` displaying which R scripts are executing
  - Improves visibility into pipeline execution flow
  - Easier debugging by clearly showing each processing step

### Changed
- **WGS QC Report Support**: Enhanced QC reporting for WGS data [`b3f8d6d`]
  - Updated `scripts/qcReport01.R` to handle WGS data without hs_metrics files
  - Added conditional check for hs_metrics files before processing hybrid selection metrics
  - Refactored getSDIR() to use get_script_dir() helper from .Rprofile
  - Sets phsm to NULL when no hs_metrics files found

- **Project Name Handling**: Improved filename consistency [`f739e7f`]
  - Added logic in `scripts/report01.R` to prepend "Proj_" to project numbers lacking prefix
  - Ensures consistent naming in output report filenames
  - Handles both Proj_XXXXX and XXXXX directory name formats

- **SV Report Refactoring**: Major code clarity improvements [`7994397`]
  - Refactored `scripts/reportSV01.R` with clarity-first approach
  - Descriptive variable names: sv_files, sv_data, sv_events (vs fof, dd, df)
  - Added clear section comments explaining each processing step
  - Switched to native pipe operator |> for R consistency
  - Grouped VAF calculations by caller (Delly, Svaba, Manta) with inline comments
  - Multi-line formatting for complex operations
  - Added sample count summary with renamed NumSVs column
  - Added SampleData sheet to Excel output
  - Functionality preserved while significantly improving readability

### Fixed
- **FACETS Purity Handling**: Preserved purity values for analysis [`9041c57`]
  - Commented out purity NA assignment for failed FACETS samples
  - Preserves original purity values for downstream analysis

### Technical Details
- **Branch Integration**: Merged multiple feature branches [`3ea2205`, `50e395a`]
  - Merged fix/post-wgs branch
  - Merged fix/filenames-report00 branch
- **Files Modified**: 5 files with 189 insertions and 52 deletions
  - bin/doPost.sh (13 insertions)
  - scripts/qcReport01.R (26 insertions, 26 deletions)
  - scripts/report01.R (7 insertions, 1 deletion)
  - scripts/reportSV01.R (73 insertions, 24 deletions)
  - scripts/reportTERT.R (44 insertions, new file)
- **Report Improvements**: Enhanced mutation reporting, WGS support, code clarity
- **Code Quality**: Tidyverse-style refactoring with improved documentation

### Commit Summary
- **Total Commits**: 8 commits since v3-rc1 (6 non-merge commits)
- **Major Features**: TERT mutation reporting, WGS QC support, code refactoring
- **Report Updates**: Non-synonymous mutation counts, SV report clarity, project naming
- **Bug Fixes**: FACETS purity handling, WGS hs_metrics compatibility

---

## v3-rc1 [2025-10-07] - Bug Fixes and Configuration Enhancements

### Added
- **Process-Specific Resource Configurations**: Added detailed resource allocation configs for IRIS cluster [`18a6468`, `61b5926`]
  - Added comprehensive CPU and memory configurations for WES pipeline processes in `conf/tempo-wes-iris.config`
  - Added detailed resource allocations for WGS pipeline processes in `conf/tempo-wgs-iris.config`
  - Includes configurations for alignment, GATK4SPARK processes (MarkDuplicates, SetNmMdAndUqTags, BaseRecalibrator, ApplyBQSR), BQSR operations, and BAM merging/indexing
  - Resources sized with dynamic scaling using task.attempt for retry scenarios
  - Time allocations use maxWallTime/minWallTime based on data size (>100GB threshold)

### Changed
- **Germline Variant Deduplication**: Enhanced germline report to handle shared normals [`98080f1`]
  - Added distinct() call to remove duplicate variant entries when same normal sample is used across multiple tumor samples
  - Deduplication based on variant position, alleles, and sample barcode while preserving all variant metadata
  - Updated report version from v2 to v3
  - Cleaned up trailing whitespace in `scripts/reportGerm01.R`

- **Germline Post-Processing**: Improved pipeline info collection and assay handling [`c2bca0d`]
  - Updated to copy all pipeline info files (html, txt, pdf) from `out/*/pipeline_info/` directories
  - Added ASSAY_TYPE detection from cmd.sh.log
  - Made SV report generation conditional - only runs reportGermSV01.R for genome assays
  - Removed premature exit statement to ensure version.txt logging completes

- **Delivery Workflow**: Simplified germline delivery structure [`907e456`]
  - Removed unnecessary mkdir commands for delivery directories
  - Switched from cp to rsync for post-processing reports
  - Consolidated output into tempo-germline/post directory
  - Simplified delivery workflow by removing nested germline subdirectory

### Performance Optimizations
- **Alignment Resource Tuning**: Reduced AlignReads CPU allocation from 16 to 8 base CPUs in WES IRIS config [`156c4c8`]
  - Maintains scaling on retry via task.attempt
  - Optimizes resource usage based on actual process requirements

### Technical Details
- **Branch Integration**: Merged multiple development branches [`24800d6`, `6047f3d`, `c6dcb1d`]
  - Merged fix/germline-report-dups branch
  - Merged fix/wgs-iris-config branch
  - Merged fix/iris-markDups branch
- **Files Modified**: 5 files with 208 insertions and 123 deletions
- **Configuration Strategy**: Process-specific resource configs for IRIS cluster optimization
- **Report Improvements**: Enhanced germline variant reporting with deduplication logic

### Commit Summary
- **Total Commits**: 9 commits since v3-pre3 (6 non-merge commits)
- **Major Features**: Process-specific IRIS configurations, germline deduplication, workflow simplification
- **Configuration Updates**: WES and WGS IRIS resource allocations, alignment CPU tuning
- **Bug Fixes**: Germline variant duplicates, pipeline info collection, delivery structure

---

## v3-pre3 [2025-10-06] - IRIS Cluster Support and WGS Optimizations

### Added
- **IRIS Cluster Support**: Complete IRIS cluster configuration and pipeline enablement
  - Added `conf/tempo-wes-iris.config` with optimized WES configuration for IRIS cluster [`6c0079a`]
  - Added `conf/tempo-wgs-iris.config` with comprehensive WGS configuration for IRIS cluster [`b54d8c2`]
  - Added `publish_dir_mode` parameter to IRIS config for nf-core compatibility [`d7cf368`]
  - Added IRIS profile configuration to tempo submodule [`c9faee7`]

### Changed
- **Cluster Configuration Management**: Enhanced cluster-specific configuration handling
  - Fixed TEMPO_PROFILE assignment to correctly use 'iris' for IRIS and 'juno' for JUNO clusters [`20f4c98`]
  - Renamed config files from `.conf` to `.config` extension for Nextflow compliance [`b54d8c2`]
  - Removed placeholder `tempo-wes-iris.conf.NEEDTOFIX` and activated final configuration [`6c0079a`]

- **Pipeline Enablement**: Enabled WES and WGS pipelines on IRIS cluster
  - Removed blocking error message preventing WES cohort processing on IRIS [`38f9af7`]
  - Removed blocking error message preventing WGS BAM processing on IRIS [`a358be6`]
  - Memory configuration issues have been resolved for IRIS cluster operation

- **Workflow Configuration**: Streamlined default workflows
  - Removed structural variant (sv) and mutsig workflows from default WES configuration [`a0d0026`]
  - Removed msisensor from default WGS workflows to align with WES configuration [`a358be6`]
  - Default workflows now focus on snv, qc, and facets analyses

- **Script Improvements**: Enhanced post-processing and file handling
  - Simplified pipeline info file collection using direct glob patterns instead of find commands [`384c0b8`]
  - Improved code maintainability with cleaner wildcard-based file copying

### Performance Optimizations
- **WGS Resource Allocation**: Optimized resource allocation for variant callers on JUNO cluster [`6c9e0be`]
  - **SomaticDellyCall**: Increased memory from 10GB to 80GB
  - **RunSvABA**: Increased CPUs to 32+ (observed 1561% parallelization), reduced memory from 4GB to 3GB
  - **SomaticRunManta**: Adjusted CPUs to 4+12*attempt, increased memory from 2GB to 16GB
  - **GermlineDellyCall**: Aligned with somatic settings (80GB memory)
  - **GermlineRunManta**: Aligned with somatic settings (16GB memory)

### Technical Details
- **Branch Integration**: Merged multiple development branches into feat/wes [`4ec875c`]
- **Files Modified**: 9 files with 221 insertions and 110 deletions
- **Configuration Strategy**: Established cluster-specific configuration files for both WES and WGS on IRIS
- **Naming Conventions**: Standardized Nextflow config file extensions to `.config`

### Commit Summary
- **Total Commits**: 11 commits since v3-pre2
- **Major Features**: IRIS cluster support, WGS performance optimization, workflow streamlining
- **Configuration Updates**: Cluster-specific configs, resource allocation improvements
- **Bug Fixes**: TEMPO_PROFILE assignment, IRIS pipeline enablement

---

## v3-pre2 [2025-09-26] - Resource Optimizations for Cordelia

### Added
- **Documentation**: Added GATK Spark MarkDuplicates memory fix notes [`ed05071`]
  - Documents solution for increased memory consumption in MarkDuplicatesSpark (issue #8307)
  - Includes working command example with spark driver and executor memory configuration
  - Resolves out-of-memory errors in GATK Spark workflows

- **Configuration Files**: New cluster-specific configuration structure
  - Created `conf/tempo-wgs-juno.conf` with comprehensive WGS-specific settings for Juno cluster
  - Added structured sections for read alignment, somatic pipeline, germline pipeline, QC, and cohort aggregation
  - Implemented 50+ process-specific configurations with optimized resource allocation

### Changed
- **Configuration Standardization**: Standardized cluster configuration naming [`9ad02e4`]
  - Renamed `conf/neo.config` to `conf/juno.config` to match cluster naming conventions
  - Updated `bin/runTempoWESCohort.sh` and `bin/runTempoWGSBam.sh` to use dynamic PIPELINE_CONFIG variable
  - Reorganized tempo config files with cluster-specific naming:
    - `tempo-wes.config` → `tempo-wes-iris.conf.NEEDTOFIX`
    - `tempo-wgs.config` → `tempo-wgs-iris.conf`

- **Resource Allocation Optimization**: Comprehensive resource allocation improvements
  - **WES Configuration** [`dd0959b`, `6a19b44`]:
    - Increased SomaticCombineChannel memory allocation (4GB base, 8GB on retry)
    - Implemented exponential CPU scaling for RunMutect2: `2 * task.attempt * task.attempt`
    - Fixed SomaticAnnotateMaf CPU allocation to match VEP forks setting (8+4*attempt CPUs)
    - Adjusted memory allocations to fixed values for better resource predictability

  - **WGS Configuration** [`2ab641a`, `5b1fd20`, `69a028f`, `3233b66`]:
    - Reset WGS configuration with TEMPO defaults optimized for Juno cluster
    - Increased minimum CPU allocation from 1 to 2 cores for 30+ processes
    - Synchronized optimizations between WES and WGS configurations
    - Implemented CPU scaling strategy: scales CPUs instead of memory on retries
    - Applied new allocation strategy to 20+ processes across somatic and germline pipelines

- **Resource Strategy Philosophy**: New approach to resource allocation [`3233b66`]
  - **Old Strategy**: Fixed CPUs + scaling memory (`nc`, `nm.GB * task.attempt`)
  - **New Strategy**: Scaling CPUs + fixed memory (`nc * task.attempt`, `nm.GB`)
  - Provides "CPU cushion" for retries while maintaining consistent memory usage
  - Leverages Juno's per-core memory allocation model effectively

### Fixed
- **Memory Management**: Resolved resource contention issues
  - Fixed RunMutect2 memory allocation to provide cushion for GATK's hardcoded `-Xmx8g` setting
  - Addressed performance issues when running multiple concurrent Mutect2 jobs
  - Optimized resource allocation for high-concurrency pipeline execution

- **Configuration Consistency**: Ensured consistent resource allocation
  - Synchronized resource settings between WES and WGS pipelines
  - Applied systematic optimizations across both exome and genome analysis workflows
  - Maintained consistency in CPU scaling and memory management strategies

### Technical Details
- **Branch Integration**: Successfully merged `optimize/post-mapping` into Cordelia branch [`19b4652`]
- **Files Modified**: 8 files with 402 insertions and 13 deletions
- **Configuration Strategy**: Implemented systematic approach to resource optimization
- **Performance Impact**: Improved pipeline throughput and reduced job startup overhead
- **Resource Efficiency**: Better utilization of Juno cluster capabilities while preventing resource contention

### Commit Summary
- **Total Commits**: 10 commits since v3.0.0
- **Major Features**: Resource optimization, configuration standardization, documentation enhancements
- **Configuration Updates**: Comprehensive resource allocation improvements for both WES and WGS
- **Performance Improvements**: Exponential CPU scaling, memory optimization, systematic resource management

---

## v3-pre [2025-09-26] - Cordelia Pre-Release 1

### Added
- **Tempo Submodule Update**: Updated tempo submodule to cordelia-01 tag [`17609d6`]
  - Advances from commit `00eb724` to `957a2949`
  - Includes 17 commits with memory optimization features, workflow enhancements, and documentation updates
  - Branch: ccs/update-250925
  - Date: 2025-09-25

### Changed
- **Documentation**: Consolidated changelog and updated version information [`1cfbc07`]
  - Enhanced changelog organization and formatting
  - Updated version tracking across project files
  - Improved documentation structure for better maintenance

### Version Update
- **Major Release**: Cordelia v3.0.0 marking significant tempo submodule advancement
- **Tempo Submodule**: Now at cordelia-01 tag with comprehensive improvements
- **Documentation**: Unified changelog documentation with tempo submodule tracking

---

## v2.3.7 [2025-09-13] - Documentation Update

### Changed
- **Documentation**: Updated output documentation to reflect current pipeline structure and file organization

---

## v2.3.6 [2025-09-12] - Bug Fixes and Script Improvements

### Fixed
- **Configuration**: Disabled scratch temp directory usage in IRIS configuration [`d01cbfe`]
- **Project Extraction**: Simplified project number extraction logic in reportSV01.R [`dd1b771`]

### Changed
- **Cluster Detection**: Enhanced cluster detection capabilities across multiple scripts
  - Added cluster detection utility function in `scripts/get_cluster_name.R` [`28ded56`]
  - Modernized cluster detection in report01.R with improved logic [`09d58d9`]
- **Script Refactoring**: Continued improvements to getClusterName.sh functionality
  - Comprehensive improvements with better error handling and debug output [`455f530`]
  - Extracted complex pipeline logic into dedicated get_zone function [`004ebcf`]
  - Improved sourcing validation and network detection [`0274596`]

### Technical Details
- **Version**: v2.3.6 release
- **Date Range**: From v2.3.5 to current HEAD (commit 1555b3b)
- **Files Modified**: 6 files across bin/, conf/, and scripts/ directories
- **Major Features**: Enhanced cluster detection, configuration fixes, script improvements

### Commit Summary
- **Total Commits**: 11 commits since v2.3.5
- **Major Features**: Cluster detection utilities, configuration improvements
- **Bug Fixes**: Scratch directory usage, project extraction logic
- **Script Updates**: getClusterName.sh enhancements, report generation improvements

---

## fix/getClustName [2025-09-07] - getClusterName.sh Improvements

### Changed
- **Check run-mode**: Check that script is being sourced and not executed directly [`0274596`]
- **Script Refactoring**: Modernized `bin/getClusterName.sh` with `ip` command fallback, consistent `[[ ]]` syntax, and extracted helper functions [`004ebcf`, `455f530`]
- **Debug Mode**: Added debug mode via `DEBUG_CLUSTER` for troubleshooting [`455f530`]


---

## feat/report-facets [2025-08-26] - Enhanced FACETS Report Generation

### Overview
Enhanced the FACETS report generation script (`scripts/reportFacets01.R`) with significant improvements to code quality, functionality, and maintainability.

### New Features

#### Multi-Sheet Excel Export
- **Added comprehensive Excel workbook generation** with three sheets:
  - `runInfo`: Sample-level metrics and purity estimates
  - `armLevel`: Chromosomal arm gains/losses across samples
  - `geneLevel`: Gene-specific copy number changes
- **Output file**: `Proj_{project_no}_CNV_Facets_v2.xlsx`

#### Enhanced Quality Control Processing
- **Replaced single facetsRpt.xlsx approach** with individual QC file processing
- **Reads multiple `.facets_qc.txt` files** from sample directories
- **Comprehensive failed sample filtering** applied across all output datasets
- **Informative logging** showing number of failed samples and their IDs

#### Library Migration
- **Switched from writexl to openxlsx** library for Excel file generation
- Maintained same functionality with improved performance

### Code Quality Improvements

#### Tidyverse Style Compliance
- **Converted to snake_case naming** throughout the script
- **Proper spacing and formatting** around operators and function calls
- **Explicit library loading** with `library()` instead of `require()`
- **Consistent string handling** using `str_*` functions

#### Code Organization
- **Added comprehensive documentation** with section headers and inline comments
- **Created helper function** `dir_ls()` to reduce code duplication
- **Eliminated duplicate segmentation processing** with `process_segmentation_file()` function
- **Clear separation of concerns** with logical code grouping

#### Enhanced Documentation
- **Header comments** explaining script purpose and outputs
- **Section-specific documentation** for each major processing step
- **Domain knowledge comments** explaining FACETS-specific concepts
- **Future maintenance context** to help understand code months later

### Technical Changes

#### File Processing Improvements
- **Robust file pattern matching** with proper regex patterns
- **Error handling** for missing files with informative warnings
- **Progress reporting** during file processing operations
- **Type conversion safety** with explicit column type handling

#### Output Filename Consistency
- **Standardized filename format** with underscore separators
- **Consistent project number inclusion** in all output files
- **Clear file naming convention** for easy identification

### Files Modified
- `scripts/reportFacets01.R`: Complete refactoring and enhancement
- `.gitignore`: Added CLAUDE.local.md exclusion

### Commit History
1. **feat: add multi-sheet Excel export to Facets report** (0af04d9)
   - Initial addition of Excel export functionality

2. **refactor: improve FACETS report script structure** (f646cce)
   - Complete refactoring for tidyverse compliance and documentation

3. **chore: add CLAUDE.local.md to gitignore** (b1a7cb9)
   - Housekeeping for development environment

4. **feat: enhance QC processing and add failed sample filtering** (6fef1a4)
   - Enhanced QC workflow and comprehensive failed sample filtering

### Benefits
- **Improved maintainability** through better code organization and documentation
- **Enhanced reliability** with robust error handling and QC processing
- **Better user experience** with informative progress messages
- **Consistent output formatting** with standardized file naming
- **Comprehensive analysis results** in consolidated Excel format

### Migration Notes
- Script now requires `openxlsx` instead of `writexl` library
- QC processing now reads from individual sample directories instead of single report file
- Output filenames include underscores for better readability
- All failed samples are consistently excluded from all output datasets

---

## v2.3.3 [2025-01-XX] - v2.3.2 [2025-01-XX]

### Added
- **Structural Variant Reporting**: New comprehensive SV reporting capabilities
  - Added `scripts/reportSV01.R` for structured SV analysis reports with BEDPE file processing [`e8571e8`]
  - Added `scripts/rsrc/read_tempo_sv.R` utility for reading tempo SV data [`e8571e8`]
  - Added `scripts/rsrc/reportCols01` configuration for SV report columns [`e8571e8`]
  - Added `scripts/rsrc/svColTypeDescriptions.csv` for SV column type descriptions [`e8571e8`]
  - Enhanced `bin/doPost.sh` with conditional SV report generation based on assay type [`abc7bb2`]

### Changed
- **Report Generation**: Improved report handling and organization
  - Updated `scripts/report01.R` to rename output file from "Report01" to "SNV_Report01" for better clarity [`5d4986d`]
  - Enhanced `bin/doPost.sh` to use `find` for dynamic report file location and improved timeline handling [`fac54b5`]
  - Modified `scripts/report01.R` to accept assay argument and conditionally exclude TMB column for non-WES assays [`90f1878`]
  - Refactored `bin/runTempoWGSBamsMin.sh` to use variable-based workflow configuration for better maintainability [`c1cefc9`]

### Technical Details
- **Version**: Development version (HEAD) based on v2.3.2
- **Date Range**: From v2.3.2 (commit 0f75608) to current HEAD (commit abc7bb2)
- **Files Modified**: 8 files across bin/, scripts/, and scripts/rsrc/ directories
- **Major Features**: SV reporting system, enhanced report organization, improved workflow configuration

### Commit Summary
- **Total Commits**: 6 commits since v2.3.2
- **Major Features**: Structural variant reporting, enhanced report handling
- **Script Updates**: Improved report generation, workflow configuration
- **Configuration Updates**: SV column descriptions, report column configurations

---

## v2.3.1 [2025-07-11] - v2.2.2 [2025-07-11]

### Added
- **Neoantigen Resource Allocation**: Enhanced resource management for neoantigen analysis
  - Added RunNeoantigen process configuration to `conf/tempo-wes.config` with CPU, memory, and time allocation [`3f970ca`]
  - Added RunNeoantigen process configuration to `conf/tempo-wgs.config` with optimized resource settings for WGS analysis [`3f970ca`]
  - Implemented task attempt-based resource scaling for improved pipeline efficiency [`3f970ca`]

### Changed
- **Tempo Submodule**: Updated tempo submodule to latest commit for improved pipeline functionality [`8060f9b`]
- **Documentation**: Enhanced patches README with additional SV Caller and Neoantigen information [`e1fb499`]

### Technical Details
- **Version**: Development version (HEAD) based on v2.2.2
- **Date Range**: From v2.2.2 (2025-07-11) to current HEAD (commit 3f970ca)
- **Files Modified**: 4 files across conf/, tempo/, and devs/ directories
- **Major Features**: Neoantigen resource allocation, tempo submodule updates

### Commit Summary
- **Total Commits**: 4 commits since v2.2.2
- **Major Features**: Neoantigen analysis resource optimization
- **Configuration Updates**: Resource allocation for RunNeoantigen process
- **Submodule Updates**: Latest tempo pipeline improvements

---

## v2.2.2 [2025-07-11] - v2.2.1 [2025-07-10]

### Added
- **Feature Patches System**: Comprehensive patch management for tempo pipeline updates
  - `devs/patches/README.md` with detailed documentation on patch system and workflow [`518fa0a`, `e1fb499`]
  - GATK4SPARK_APPLYBQSR module update patch for improved variant calling [`98444cb`]
  - Delly and htslib upgrade patch for enhanced structural variant detection [`32f330c`]
  - SVABA container and configuration update patches for improved SV calling [`e1913c5`]

- **Documentation Enhancements**: New documentation and roadmap
  - `devs/ndsDevsTempoBranches` documentation for branch management [`7f083cc`]
  - `devs/roadmap-tempo-ccs.md` comprehensive roadmap for tempo pipeline development [`7f083cc`]
  - Enhanced README with SV Caller and Neoantigen information [`e1fb499`]

### Changed
- **Version Management**: Updated version information across project
  - Bumped version to v2.2.2 in README.md and VERSION.md [`72afc50`]
  - Updated tempo submodule to latest commit for improved pipeline functionality [`2fe581d`, `5cdcb7c`]

- **Configuration Improvements**: Enhanced configuration management
  - Clarified commit message generation rules in .cursorrules [`b03ea88`]
  - Removed redundant sections from .cursorrules for cleaner configuration [`5d18f8a`]
  - Updated cursor AI rules for better clarity and consistency [`bc6d340`, `e123466`]

- **Resource Allocation**: Optimized WGS configuration
  - Streamlined tempo-wgs.config with improved resource allocation settings [`c455c56`]
  - Enhanced IRIS cluster configuration with increased queue size [`e7fe01d`]

- **Script Enhancements**: Improved WGS BAM processing
  - Enhanced `bin/runTempoWGSBamsMin.sh` with cluster detection capabilities [`c774dd8`]
  - Fixed BAM mapping variable in WGS script for improved reliability [`e8e71c4`]
  - Added cluster-specific file path support for WES gene frequency reporting [`b88c183`]

### Fixed
- **Bug Fixes**: Various improvements and corrections
  - Fixed BAM mapping variable in WGS script for proper file handling [`e8e71c4`]
  - Corrected resource allocation parameters in WGS configuration [`c455c56`]

### Technical Details
- **Version**: Released v2.2.2 as stable release [`72afc50`]
- **Date Range**: From v2.2.1 (2025-07-10) to current HEAD (commit e1fb499)
- **Files Modified**: 15+ files across devs/, conf/, bin/, scripts/, and root directories
- **Major Features**: Feature patches system, enhanced documentation, improved configuration management

### Commit Summary
- **Total Commits**: 20 commits since v2.2.1
- **Major Features**: Patch management system, comprehensive documentation, configuration improvements
- **Configuration Updates**: Resource optimization, commit message rules, cursor AI integration
- **Bug Fixes**: Script reliability, resource allocation, configuration cleanup

---

## v2.2.1 [2025-07-10] - v1.5.0 [2024-XX-XX]

### Added
- **Cluster Configuration**: New cluster-specific configuration files and scripts
  - `conf/iris.config` for IRIS cluster configuration with SLURM executor [`df6b105`]
  - `conf/juno.config` for cluster-specific configuration options [`18bd8c0`]
  - `bin/getClusterName.sh` script to determine cluster name based on zone configuration [`cad7e47`]
  - `00.SETUP.sh` script for Nextflow installation [`cbfcfed`]

- **FASTQ Processing**: Enhanced FASTQ file processing capabilities
  - `scripts/attic/fastqDir2Tempo.R` for directory-based FASTQ file processing with R1-R2 consistency checks [`2eb3115`]
  - Improved `scripts/fastq2tempo.R` with better input handling and mapping generation [`2eb3115`]

- **Cursor AI Integration**: Added comprehensive cursor AI rules and configuration
  - Enhanced `.cursorrules` with commit message generation guidelines [`e046a9e`, `e123466`, `bc6d340`, `5d18f8a`]
  - Added cluster-specific file path for WES gene frequency [`b88c183`]

### Changed
- **Major Version Updates**: Significant version progression
  - Bumped to version v2.1.x for EOS Branch development [`622b1b8`]
  - Released v2.2.0 as Iris-specific release [`c9f72c0`]
  - Released v2.2.1 as frozen release [`c1c9d56`]

- **Configuration Management**: Comprehensive configuration refactoring
  - Refactored `conf/tempo-wes.config` and `conf/tempo-wgs.config` to streamline configuration options [`a741508`]
  - Enhanced tempo-wes.config with new process configurations for improved resource allocation [`7b84e46`]
  - Updated tempo-wgs.config with new parameters and process configurations [`bb65192`]
  - Added resource allocation settings for additional processes in tempo-wes.config [`fcc6cf9`]

- **Script Enhancements**: Major improvements to run scripts
  - Enhanced `bin/runTempoWESCohort.sh` with improved cluster configuration handling [`6cf77ac`]
  - Added reference_base variable to runTempoWESCohort.sh for improved configuration management [`67be868`]
  - Enhanced `bin/runTempoWGSBamsMin.sh` with cluster detection capabilities [`c774dd8`]

- **Resource Allocation**: Optimized resource allocation across configurations
  - Updated resource allocation for RunMutect2 in tempo-wgs.config [`08f11ee`]
  - Enhanced tempo-wes.config and tempo-wgs.config with new parameters [`bb65192`]
  - Updated WGS config for resource allocation [`c455c56`]
  - Increased queue size and updated cluster options [`e7fe01d`]

- **Submodule Management**: Updated tempo submodule tracking
  - Updated tempo submodule to track develop branch [`f5ad132`, `28cdd42`, `fb4a0f8`, `596224e`]
  - Updated tempo submodule to eos-devs branch [`271e38e`, `a0e65c3`, `32eef59`, `bf5c030`]
  - Updated tempo submodule to latest commit [`5cdcb7c`]

### Fixed
- **Bug Fixes**: Various bug fixes and improvements
  - Fixed bug with new PROJECT_ID variable [`92ffede`]
  - Fixed regex in fastq2tempo.R for R2 file naming and updated pairing column name [`238691f`]
  - Fixed maxWallTime on IRIS [`2181d7b`]
  - Corrected BAM mapping variable in WGS script [`e8e71c4`]

- **Configuration Issues**: Resolved configuration problems
  - Removed non-functional reference_base parameter from tempo-wes.config [`d391b34`]
  - Removed parameters from tempo-wgs.config that are not functional [`a7bdaf9`]
  - Removed redundant sections from .cursorrules [`5d18f8a`]

### Removed
- **Deprecated Scripts**: Cleanup and reorganization
  - Moved old scripts to attic directory (`bin/attic/v1.0.4/`) for archival
  - Moved various scripts to stash directory for potential future use
  - Removed custom configs for WES runs in favor of pure juno.config [`01f053d`]

### Technical Details
- **Version**: Multiple major version releases (v2.0.1, v2.2.0, v2.2.1)
- **Date Range**: From v1.5.0 to current HEAD (commit 5cdcb7c)
- **Files Modified**: 25+ files across bin/, conf/, scripts/, and root directories
- **Major Features**: Cluster-specific configurations, enhanced FASTQ processing, cursor AI integration

### Commit Summary
- **Total Commits**: 50+ commits since v1.5.0
- **Major Features**: IRIS cluster support, enhanced configuration management, improved script handling
- **Configuration Updates**: Resource optimization, cluster-specific configs, process improvements
- **Bug Fixes**: Various script and configuration fixes

---

## v1.5.0 [2025-06-22] - v1.0.4 [2024-10-30:ffa846e]

### Added
- **Germline Analysis Pipeline**: Complete implementation of germline variant analysis pipeline
  - New script `bin/runTempoWESBAMsGermline.sh` for WES germline analysis starting from BAMs [`1ef8647`]
  - New script `bin/runTempoWGSBamsGermline.sh` for WGS germline analysis starting from BAMs [`b29828f`]
  - New script `bin/runTempoWESCohortGermline.sh` for WES cohort germline analysis
  - New script `bin/deliverGermline.sh` for germline delivery workflow [`7728bbf`]
  - Enhanced germline post-processing script `bin/doGermlinePost.sh` (version 2) [`e96a17c`]
  - New germline report generation script `scripts/reportGerm01.R` with QC data integration [`6887028`]

- **BAM-based Analysis**: New workflows for analysis starting from BAM files
  - `bin/runTempoWESBams.sh` for WES analysis from BAMs [`8b1136e`]
  - `bin/runTempoWGSBamsFULL.sh` for full WGS analysis from BAMs
  - `bin/runTempoWGSBamsNoSVs.sh` for WGS analysis without structural variants [`0f39b7b`]

- **Downsampling Tools**: New BAM downsampling functionality
  - `scripts/downSampleBam.sh` for BAM downsampling [`759f72e`]
  - `scripts/downSampleArgs.R` for downsampling argument processing

- **Reporting Enhancements**: New and improved reporting capabilities
  - `scripts/reportFacets01.R` for Facets copy number analysis reports [`9eeee20`]
  - Enhanced `scripts/multiSVReport01.R` for structural variant reporting
  - `scripts/qcReport01.R` for quality control reporting
  - Facets QC columns resource file `scripts/rsrc/facetsQCCols` [`4710fc9`]

- **WGS BAM Processing**: New R script `scripts/wgsBAM2Tempo.R` for WGS BAM to Tempo conversion

- **Common Genes/Fusions**: Added Common Genes/Fusions functionality [`633d3fb`]

- **Facets Integration**: Added facets information and reporting [`4710fc9`, `9eeee20`]

- **Samtools Integration**: Added samtools indexing requirement [`1301127`]

### Changed
- **LSF Resource Management**: Comprehensive updates to LSF resource allocation
  - Enhanced `conf/tempo-wgs.config` with improved resource allocation for various processes [`37a0340`]
  - Massive updates to LSF parameters for better performance and resource utilization [`589e268`]
  - Adjusted CPU and time resources for optimal processing [`d8501e1`]

- **Script Unification**: Cleanup and unification of WES and WGS run scripts [`8ab5777`]
  - Standardized parameter names and usage instructions [`09fe7b5`]
  - Improved script compatibility for both foreground and background execution [`8c3fdb7`]

- **Germline Processing**: Major improvements to germline variant processing
  - Enhanced MAF file processing for germline variants [`968a7c7`]
  - Fixed normal (germline) MAF output generation [`5d2aace`]
  - Added pairing file requirement for germline analysis [`61b073e`]
  - Improved logging for interactive runs [`b97a000`]

- **Coverage Parameters**: Added customizable coverage parameters to scripts [`c6615aa`]

- **Version Information**: Updated version info [`75349fe`]

### Fixed
- **Bug Fixes**: Various bug fixes and improvements
  - Fixed bug in `scripts/downSampleBam.sh` downsampling functionality [`83dccd5`]
  - Bugfix in time computation for processing workflows [`9dce571`]
  - Fixed script compatibility for both foreground and background execution [`8c3fdb7`]
  - Fixed logging issues for interactive runs [`b97a000`]

### Removed
- **Deprecated Scripts**: Cleanup of outdated functionality
  - Archived old WGS script (`bin/attic/runTempoWGSCohort.sh`) [`e617c6f`]
  - Removed old germline post-processing script (`bin/attic/doGermlinePost.sh`) [`f0d1b58`]

### Technical Details
- **Version**: 32 commits ahead of v1.0.4 (commit e96a17c)
- **Date Range**: From v1.0.4 (2024-12-19) to current HEAD
- **Files Modified**: 19 files across bin/, conf/, and scripts/ directories

### Commit Summary
- **Total Commits**: 32
- **Major Features**: Germline analysis pipeline, BAM-based workflows, downsampling tools
- **Configuration Updates**: LSF resource optimization, script unification
- **Bug Fixes**: Downsampling, time computation, logging improvements

---

## [v1.0.4] - Previous Release
- Update tempo to deal with oncokb issue [`ffa8f6e`]
- Submodule update to tempo commit b85adb4

---

*This changelog documents all changes from v1.0.4 (commit ffa8f6e) to the current HEAD (commit e96a17c).* 