# Changelog

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