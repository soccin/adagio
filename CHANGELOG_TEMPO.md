# CHANGELOG - Tempo Submodule

This changelog documents all changes to the tempo submodule from commit `e189e262` to current HEAD.

---

## [Current HEAD: 00eb724b] - 2025-09-24

### Documentation Updates
- **docs: update README with nf-core integration status** [`00eb724b`]
  - Updated README documentation to reflect nf-core integration status
  - Author: Nicholas D. Socci

- **docs: document upstream nf-core/markdup_spark merge** [`76a56330`]
  - Added documentation for the upstream nf-core/markdup_spark merge
  - Author: Nicholas D. Socci

### Upstream Integration
- **Merge remote-tracking branch 'upstream/nf-core/markdup_spark' into update/markdup_spark** [`f561b355`]
  - Integrated upstream nf-core/markdup_spark branch changes
  - Author: Nicholas D. Socci

- **rename: CHANGELOG.md to CHANGELOG_nds.md before upstream merge** [`df008f34`]
  - Renamed main changelog to avoid conflicts during upstream merge
  - Author: Nicholas D. Socci

---

## nf-core/markdup_spark Integration - 2025-09-12 to 2025-08-21

### Code Cleanup
- **remove another debug view code** [`833d681e`]
  - Cleaned up additional debug view statements
  - Author: gongyixiao

- **remove debug view command** [`9f892c8a`]
  - Removed debug view commands from codebase
  - Author: gongyixiao

### BAM Processing Improvements
- **merge bams after settags** [`41d08955`]
  - Updated BAM processing workflow to merge BAMs after setting tags
  - Author: tempo bot

- **parallelize setnmmdanduqtags** [`4a1ffc91`]
  - Parallelized SETNMMDANDUQTAGS processing for improved performance
  - Author: tempo bot

- **parallelize SETNMMDANDUQTAGS step by split intervals** [`11821735`]
  - Implemented interval splitting for parallel SETNMMDANDUQTAGS execution
  - Author: tempo bot

### Module Integration and Development
- **add SETNMMDANDUQTAGS step** [`696c92c7`]
  - Added new SETNMMDANDUQTAGS processing step to pipeline
  - Author: Yixiao

- **Convert picard_setnmmdanduqtags to a local module with custom modifications** [`243f9f27`]
  - Converted Picard SETNMMDANDUQTAGS to local module with customizations
  - Author: Yixiao

- **install picard/setnmmdanduqtags module** [`2301f185`]
  - Installed Picard SETNMMDANDUQTAGS module
  - Author: Yixiao

### Branch Merges and Updates
- **Merge branch 'nf-core/markdup_bqsr' of https://github.com/mskcc/tempo into nf-core/markdup_spark** [`f34fc310`]
  - Merged nf-core/markdup_bqsr branch into nf-core/markdup_spark
  - Author: Yixiao

- **Merge branch 'develop' of https://github.com/mskcc/tempo into nf-core/markdup_spark** [`429b008b`]
  - Merged develop branch changes into nf-core/markdup_spark
  - Author: Yixiao

- **Merge branch 'develop' of https://github.com/mskcc/tempo into nf-core/markdup_bqsr** [`030cb174`]
  - Merged develop branch into nf-core/markdup_bqsr
  - Author: Yixiao

### Bug Fixes and Improvements
- **update gatk4spark/applybqsr to fix space issue** [`53e6ff98`]
  - Fixed space-related issues in GATK4 Spark APPLYBQSR module
  - Author: Yixiao

---

## nf-core Integration Foundation - 2024-11-20 to 2025-02-03

### Resource and Configuration Updates
- **fix conflicts** [`18f6c0ac`]
  - Resolved merge conflicts during integration
  - Author: Yixiao

- **resource configs** [`832ac5e1`]
  - Updated resource configuration settings
  - Author: Yixiao

- **swap with markduplicates spark version** [`325dac23`]
  - Switched to Spark version of MarkDuplicates
  - Author: Yixiao

### Exome-Specific Optimizations
- **for exomes** [`32e3d909`]
  - Added exome-specific processing optimizations
  - Author: Yixiao

- **fixes** [`a76fa232`, `7ebbfde3`]
  - Multiple bug fixes and improvements
  - Author: Yixiao

### BQSR Module Integration
- **bqsr_scatter modules added** [`b8d36bb6`]
  - Added BQSR scatter modules for parallel processing
  - Author: Yixiao

### nf-core Package Integration
- **initial working version** [`e7fcdaa2`]
  - First working version of nf-core integration
  - Author: Yixiao

- **installed 3 nf-core packages** [`d0d212e1`]
  - Integrated three nf-core packages into the pipeline
  - Author: Yixiao

- **correction** [`c5535270`]
  - Made corrections to nf-core integration
  - Author: Yixiao

- **resolve conflicts** [`ac55745c`]
  - Resolved conflicts during nf-core package integration
  - Author: Yixiao

### nf-core Template Foundation
- **initial template build from nf-core/tools, version 2.7.2** [`fe79b466`, `d8404d67`]
  - Built initial template using nf-core/tools version 2.7.2
  - Author: Yixiao

### Parameter and Configuration Additions
- **add params.publish_dir_mode** [`49d08751`]
  - Added parameter for publish directory mode configuration
  - Author: Yixiao

- **add params.outdir** [`b9e4087f`]
  - Added output directory parameter
  - Author: Yixiao

- **add params.tracedir** [`3d43defb`]
  - Added trace directory parameter for pipeline monitoring
  - Author: Yixiao

### Build and Testing Updates
- **fix travis openjdk8 to openjdk11** [`ed17c4bd`]
  - Updated Travis CI configuration from OpenJDK 8 to 11
  - Author: Yixiao

- **fix travis test nextflow version requirement** [`ab8acc73`]
  - Fixed Nextflow version requirements in Travis tests
  - Author: Yixiao

### Conflict Resolution
- **resolve conflicts 4** [`255785d4`]
- **resolve conflict 2** [`bc145147`]
- **resolve conflict 1** [`f53dc419`]
- **resolve conflicts** [`b32d3777`]
  - Multiple rounds of conflict resolution during nf-core integration
  - Author: Yixiao

---

## Summary

### Major Changes Since e189e262:
- **nf-core Integration**: Complete integration with nf-core framework and tools
- **MarkDuplicates Enhancement**: Migration to Spark-based MarkDuplicates with SETNMMDANDUQTAGS
- **BQSR Improvements**: Added scatter-based BQSR processing for better parallelization
- **Documentation Updates**: Comprehensive documentation of integration status
- **Resource Optimization**: Updated configurations for exome-specific processing
- **Code Cleanup**: Removed debug statements and improved code quality

### Technical Details:
- **Date Range**: 2025-02-03 to 2025-09-24 (e189e262 to 00eb724b)
- **Total Commits**: 37 commits
- **Main Contributors**: Nicholas D. Socci, Yixiao, gongyixiao, tempo bot
- **Major Features**: nf-core framework adoption, Spark-based processing, improved parallelization

### Key Improvements:
1. **Performance**: Parallelized processing with interval splitting
2. **Integration**: Full nf-core framework compliance
3. **Modularity**: Local module customizations with upstream compatibility
4. **Documentation**: Enhanced README and integration status documentation
5. **Resource Management**: Optimized configurations for different assay types

---

*This changelog documents all tempo submodule changes from commit e189e262 (merge: 'enhancement/neoantigen_parallel') to current HEAD 00eb724b (docs: update README with nf-core integration status).*