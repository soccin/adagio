# Changelog

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

### Summary
Complete refactoring and enhancement of the FACETS report generation script (`scripts/reportFacets01.R`) with significant improvements to code quality, functionality, and maintainability. Major additions include multi-sheet Excel export functionality with comprehensive analysis results (runInfo, armLevel, geneLevel), enhanced quality control processing that reads individual QC files from sample directories, and comprehensive failed sample filtering across all datasets. The script now follows tidyverse style guidelines with snake_case naming, proper documentation, helper functions for code reuse, and switched from writexl to openxlsx library. These changes provide improved maintainability through better code organization, enhanced reliability with robust error handling, and a better user experience with informative progress messages and standardized output formatting.

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