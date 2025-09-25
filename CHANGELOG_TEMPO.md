# TEMPO Submodule Changelog

This document tracks changes in the tempo submodule from commit `0f8d1ce5bd1` to the current devs branch.

## [a37c341b] - 2025-09-24 - Documentation and Branch Updates

### Documentation
- **README Update**: Updated README with devs branch summary, replacing outdated eos-devs branch documentation
- **Branch Modernization**: Highlighted major modernization with nf-core framework integration
- **Executive Summary**: Added clear overview of Spark-based processing optimizations and neoantigen control improvements

## [98744213] - 2025-09-24 - Major Branch Merge

### Integration
- **Merge**: Merged `merge/ccs-markdup_spark` branch into `eos-devs`
- **Changelog Updates**: Updated changelog with merge branch changes
- **Spark Integration**: Completed integration of nf-core/markdup_spark with Spark optimization

## [506d1c75] - 2025-09-24 - Core Spark Integration

### Major Features
- **nf-core Integration**: Merged nf-core/markdup_spark with comprehensive Spark optimization
- **Changelog Reorganization**: Renamed CHANGELOG.md to CHANGELOG_nds.md for better organization
- **File Cleanup**: Removed temporary documentation files (DISABLE_NEOANTI.md, CHECKPOINT_CLAUDE.md)

## [b6199634] - 2025-09-24 - Neoantigen Control Enhancement

### Configuration
- **Neoantigen Prediction**: Disabled neoantigen prediction by default for improved performance
- **Documentation**: Added comprehensive neoantigen disable documentation
- **Claude Integration**: Added Claude Code guidance and checkpoint files for development workflow

## Mark Duplicates Spark Optimization Series

### [696c92c7] - SETNMMDANDUQTAGS Implementation
- **New Process**: Added SETNMMDANDUQTAGS step for enhanced BAM processing
- **Module Conversion**: Converted picard_setnmmdanduqtags to local module with custom modifications
- **Picard Integration**: Installed and configured picard/setnmmdanduqtags module

### [11821735] - [4a1ffc91] - Parallelization Enhancements
- **Parallel Processing**: Parallelized SETNMMDANDUQTAGS step by split intervals
- **BAM Merging**: Enhanced BAM merging after setting tags
- **Performance Optimization**: Improved processing efficiency through parallelization

### [325dac23] - [832ac5e1] - Resource and Configuration Updates
- **Spark Integration**: Swapped to MarkDuplicates Spark version for better performance
- **Resource Configs**: Updated resource allocation configurations
- **Exome Support**: Enhanced support for exome processing workflows

## nf-core Framework Integration Series

### [fe79b466] - [d8404d67] - Initial nf-core Template Build
- **Framework Integration**: Initial template build from nf-core/tools, version 2.7.2
- **Parameter Updates**: Added essential nf-core parameters (outdir, publish_dir_mode, tracedir)
- **Travis Improvements**: Fixed Travis CI configuration for Java 11 and Nextflow version requirements

### [d0d212e1] - [e7fcdaa2] - Module Installation and Implementation
- **nf-core Packages**: Installed 3 core nf-core packages for enhanced functionality
- **BQSR Modules**: Added BQSR scatter modules for improved variant calling
- **Working Version**: Established initial working version with core functionality

## Bug Fixes and Improvements

### [53e6ff98] - GATK4Spark Enhancement
- **Space Issue Fix**: Updated gatk4spark/applybqsr to resolve space handling issues
- **Processing Reliability**: Improved reliability of BQSR application process

### [9f892c8a] - [833d681e] - Code Cleanup
- **Debug Removal**: Removed debug view commands and code for cleaner implementation
- **Code Quality**: Enhanced code maintainability through cleanup efforts

## Branch Management and Conflicts

### Multiple Merge Operations
- **Conflict Resolution**: Resolved multiple merge conflicts during nf-core integration
- **Branch Synchronization**: Synchronized develop branch changes with feature branches
- **Integration Stability**: Maintained stability during complex multi-branch merges

## Technical Improvements

### Performance Enhancements
- **Spark Optimization**: Leveraged Apache Spark for improved MarkDuplicates performance
- **Parallel Processing**: Enhanced parallelization across multiple pipeline steps
- **Resource Allocation**: Optimized resource allocation for better cluster utilization

### Development Workflow
- **Documentation**: Added comprehensive development documentation and guidance
- **CI/CD**: Improved continuous integration setup with updated Java and Nextflow versions
- **Code Quality**: Enhanced code organization and maintainability standards

---

## Summary

This changelog covers significant modernization of the tempo pipeline from commit `0f8d1ce5bd1` to `a37c341b`, featuring:

- **Major nf-core Framework Integration**: Complete adoption of nf-core standards and tools
- **Apache Spark Optimization**: Enhanced MarkDuplicates processing with Spark backend
- **Neoantigen Control**: Improved configuration control for neoantigen prediction
- **Parallel Processing**: Enhanced parallelization across multiple pipeline components
- **Development Workflow**: Improved documentation and development tools integration
- **Code Quality**: Comprehensive cleanup and modernization of codebase

**Total Commits**: 42 commits spanning major architectural improvements and optimizations.