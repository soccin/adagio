# CHANGELOG - Features Branch

## feat/report-facets

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