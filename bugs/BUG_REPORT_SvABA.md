# BUG REPORT: SvABA integration

Date: 2026-08-16
Branch: `feat/ffpe-sv`
Source: code review of `SomaticRunSvABA.nf` / `GermlineRunSvABA.nf`

Deferred findings. None are fixed. Parked pending a broader pipeline
refactor.

## 1. Merge threshold silently flips 1 -> 2 when a third caller is added

`tempo/modules/process/GermSV/GermlineMergeSVs.nf:27` (and the somatic
twin) sets `passMin = callerNames.size() > 2 ? 2 : 1`. The SvABA commits
took the caller count from 2 to 3 (`sv_wf.nf:71`, `germlineSV_wf.nf:56`),
so `passMin` went 1 -> 2. Single-caller SVs are then dropped outright by
`filter-sv-vcf.py:77` (`if num_callers < min_pass: continue`), not just
marked non-PASS.

Currently inert: only somatic WES and germline take that branch, and
neither is in scope. Somatic WGS uses the 4-caller brass branch and was
already at `passMin = 2`. This becomes live the moment WES SV or germline
SV is turned on, and the threshold change is invisible in the diff
because the formula itself never changed.

## 2. SvABA lost its test-profile guard

`tempo/modules/subworkflow/sv_wf.nf:44` invokes `SomaticRunSvABA`
unconditionally; `brass_wf` (line 55) kept
`workflow.profile != "test"`. Under `-profile test` the else-branch
`groupTuple(size:3)` at line 71 now requires an SvABA tuple, so a SvABA
failure on the truncated `smallGRCh37` reference stalls
`SomaticMergeSVs` and everything downstream instead of skipping a caller.

## 3. Unanchored `rm -f *germline*` can delete required output

`tempo/modules/process/SV/SomaticRunSvABA.nf:31`. `outputPrefix` is in
every SvABA filename, so a sample ID containing `germline` (e.g.
`s_C_xxxx_germline_d`) makes the glob match
`${outputPrefix}.svaba.somatic.sv.vcf.gz` and `.log`; the `bcftools
reheader` at line 37 then fails. Fix: `rm -f ${outputPrefix}.svaba*germline*`.

## 4. Germline process publishes unfiltered VCFs

`tempo/modules/process/GermSV/GermlineRunSvABA.nf:3` has no cleanup step,
unlike the somatic process which strips intermediates for space. Copies
`${idNormal}.svaba.unfiltered.{sv,indel}.vcf.gz` into the delivery tree
un-renamed (sample column is still the BAM filename).

## Fixed already, not deferred

`-p ${task.cpus * 2}` -> `-p ${task.cpus}` in both modules. The cgroup
capped the task at `task.cpus` regardless (%cpu 3620 against a 3700
allocation over 122 measured tasks), so the doubled thread count bought
no throughput and only cost memory. See the note in
`conf/tempo-wgs-iris.config`.
