# Changelog



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