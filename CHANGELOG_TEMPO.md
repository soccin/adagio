# CHANGELOG - Tempo Submodule

This changelog documents all changes to the tempo submodule from commit `00eb724` to `a7ecd35a` (25 commits total).

## Changes: ed83b1b0..a7ecd35a (2026-09-05)

Branch moved from `ccs/update-250925` to `devs/iris`.

### QC
- **a7ecd35a**: Merge branch 'fix/qcqualmap' into devs/iris (Nicholas D. Socci, 2026-09-05)
- **d83b4150**: feat(qc): add skipQualimap option to bypass bamqc (Nicholas D. Socci, 2026-09-05)
  - New `params.skipQualimap` (default `false`) in `nextflow.config`. When set,
    `QcQualimap` emits its declared outputs without running `qualimap bamqc`.
    The rawdata stub is a valid empty tar (`--files-from /dev/null`) because
    all three MultiQC processes untar it; a zero-byte file would kill them.
  - `qualimap bamqc -nt` changed from `task.cpus * 2` to `task.cpus`. This is
    shared code and also applies to JUNO, where the worker pool is idle ~97%
    of the run; it is a thread-count reduction, not a behaviour change.
  - Consumed by adagio via `skipQualimap = true` in
    `conf/tempo-wgs-iris.config` (adagio `44e88f7`). WES and JUNO keep the
    `false` default, so bamqc still runs there.
  - Trade-off: `SampleRunMultiQC`/`SomaticRunMultiQC` lose the Coverage,
    % Aligned, Error rate and Ins. size columns and the qualimap plots. The
    % Aligned criterion drops out of QC_Status silently rather than failing.
    Conpair, alfred and facets QC are unaffected.

---

## Changes: 8e6312e0..ed83b1b0 (2026-08-16)

### SV Callers
- **ed83b1b0**: Merge branch 'feat/ffpe-sv' into ccs/update-250925 (Nicholas D. Socci, 2026-08-16)
- **2ff7e96a**: docs(adagio): document SvABA ENCODE blacklist (Nicholas D. Socci, 2026-08-16)
- **356fa8db**: fix(sv): use adagio ENCODE exclude for Delly (Nicholas D. Socci, 2026-08-16)
- **e591a3e8**: feat(svaba): add ENCODE blacklist via -B (Nicholas D. Socci, 2026-08-16)
- **49773e01**: fix(svaba): match -p threads to task.cpus (Nicholas D. Socci, 2026-08-16)

Both SV region files resolve through `${projectDir}/../rsrc/` and
`defineReferenceMap` validates them at startup with `checkIfExists`, so tempo
now depends on its parent adagio checkout for every run, not only for SV
workflows.

---

## Changes: 957a2949..8e6312e0 (2025-10-06)

### IRIS Profile Support
- **8e6312e0**: docs(adagio): update README with iris profile and date (Nicholas D. Socci, 2025-10-06)
- **c7a3a026**: feat(iris): add iris profile configuration (Nicholas D. Socci, 2025-10-06)

## Changes: 00eb724..957a2949 (2025-09-25)

### Documentation Updates
- **957a2949**: docs(adagio): update README with patch merge info (Nicholas D. Socci, 2025-09-25)
- **8a57ec36**: docs(adagio): update version tracking with recent merges (Nicholas D. Socci, 2025-09-25)
- **38e5e5ae**: docs: add Adagio version tracking documentation (Nicholas D. Socci, 2025-09-25)

### Memory Optimization Features
- **f3239627**: feat(adagio): add memory optimization patches for markDups (Nicholas D. Socci, 2025-09-25)
- **18de6d21**: Update MergeBamsAndMarkDuplicates process to use params value `max_records_in_ram` to set argument for MarkDups (Nicholas D. Socci, 2025-07-06)
- **6510d859**: Add default max_records_in_ram parameter to juno.config (Nicholas D. Socci, 2025-07-06)

### Workflow Enhancements
- **b43dca30**: separating_hlatyping_and_lohhla_wf (Yixiao, 2025-08-28)
- **8ec3c85d**: enable MetaDataParser optional input (Yixiao, 2025-08-28)
- **67a23782**: mv RunNeoantigen.nf to separate process subdir (Yixiao, 2025-08-27)
- **5b6c4e4e**: separate RunNeoantigen from SNV (Yixiao, 2025-08-27)

### Upstream Merges
- **4b94163a**: Merge remote-tracking branch 'upstream/enhancement/neoantigen_parallel' into merges-250925 (Nicholas D. Socci, 2025-09-25)
- **2b80a1af**: Merge remote-tracking branch 'upstream/update/svaba' into merges-250925 (Nicholas D. Socci, 2025-09-25)
- **e90caa7a**: Merge remote-tracking branch 'upstream/feature/upgrade_delly_v126' into merges-250925 (Nicholas D. Socci, 2025-09-25)

### Branch Merges
- **d88e5d30**: Merge branch 'patch/01-maxRecsInRam' into ccs/update-250925 (Nicholas D. Socci, 2025-09-25)
- **a5286229**: Merge branch 'merges-250925' into ccs/update-250925 (Nicholas D. Socci, 2025-09-25)
- **9bb43035**: Merge branch 'enhancement/separating_hlatyping_and_lohhla_wf' into ccs/update-250925 (Nicholas D. Socci, 2025-09-25)
- **34d35803**: Merge branch 'enhancement/separating_neoantigen' of https://github.com/mskcc/tempo into enhancement/separating_hla_and_lohhla_wf (Yixiao, 2025-08-28)

---
