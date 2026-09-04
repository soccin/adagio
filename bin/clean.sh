#!/bin/bash
#
# Remove pipeline outputs and Nextflow state from the current project folder.
# Run from the project directory (where out/ lives).
#

rm -vrf out* work/ .nextflow.log* trace* report.html timeline.html \
    fileTracking.tsv bamMapping.tsv
