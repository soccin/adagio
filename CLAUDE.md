# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Adagio** is a genomic sequencing pipeline framework - a customized derivation of the Tempo bioinformatics pipeline for processing paired-end whole-exome sequencing (WES) and whole-genome sequencing (WGS) data from human cancer samples with matched normal controls.

## Core Technologies

- **Nextflow DSL2** - Primary workflow orchestration
- **Bash** - Execution scripts and cluster management
- **R** - Analysis reports and data visualization
- **Singularity** - Containerized tool execution
- **HPC Clusters** - Designed for Juno (MSKCC) and Iris environments

## Essential Commands

### Initial Setup
```bash
./00.SETUP.sh                    # Install nextflow in bin/
source SETENVRC                  # Set environment variables and paths
```

### Pipeline Execution
```bash
# WES analysis
./bin/runTempoWESCohort.sh [mapping_file] [outname]

# WGS analysis
./bin/runTempoWGSBam.sh [mapping_file] [outname]

# Resume interrupted runs
nextflow run tempo/dsl2.nf -resume [original_args]

# Monitor runs
./bin/monitor.sh

# Clean temporary files
clean  # Alias for removing work/, out*, logs, etc.
```

## Architecture

### Core Components
- **tempo/** - Submodule containing main Nextflow workflow (dsl2.nf)
- **bin/** - Execution scripts (runTempo*.sh, getClusterName.sh, post-processing)
- **scripts/** - R-based reporting (report01.R, reportSV01.R, reportFacets01.R, etc.)
- **conf/** - Cluster and analysis-type configurations

### Workflow Modules
The pipeline supports multiple analysis workflows that can be enabled/disabled:
- **SNV** - Single nucleotide variants (Mutect2, Strelka2, HaplotypeCaller)
- **SV** - Structural variants (Manta, Delly, SvABA)
- **QC** - Quality control metrics
- **FACETS** - Copy number analysis
- **Germline** - Germline variant calling
- **Neoantigen** - Neoantigen prediction
- **MSI** - Microsatellite instability

### Data Flow
1. Input: Sample mapping files (TSV) with tumor-normal pairs
2. Processing: Nextflow orchestrates parallel module execution
3. Output: Structured results with automated report generation
4. Post-processing: `doPost.sh` and `doGermlinePost.sh` for final reports

## Development Notes

### Version Management
- Current version: v2.3.7
- Tempo submodule tracks separately
- Clone with `--recurse-submodules`

### Commit Standards (from .cursorrules)
- Conventional commits: `type(scope): description`
- Scopes: tempo, pipeline, docs, scripts, conf
- 50 character limit for subject
- Reference specific files/workflows affected
- Append `#cursor` tag to commit body

### Cluster Integration
- Automatic cluster detection (Iris, Juno)
- Environment-specific singularity cache and temp directories
- Dynamic resource allocation per cluster capabilities

### Resume Capability
Nextflow supports resuming interrupted runs:
1. Use `-resume` flag with original arguments
2. Move trace.txt, *.html, *.tsv to passN/ directory first
3. Template resume scripts available in scripts/

### Key Environment Variables
- `NXF_SINGULARITY_CACHEDIR` - Singularity container cache
- `TMPDIR` - Temporary file location
- `PATH` - Include bin/ directory for nextflow access

### Output Structure
- Main results in workflow-specific directories
- Reports generated in post/reports/ and germline/
- Comprehensive Excel outputs for major analysis types

## Documentation
- Online docs: https://cmotempo.netlify.app (master) or https://deploy-preview-983--cmotempo.netlify.app (develop)
- Installation details in docs/installation.md