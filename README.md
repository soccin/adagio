# ADAGIO

A derivation of [_Tempo_](https://github.com/mskcc/tempo).

Some nice [adagios](https://open.spotify.com/playlist/3o1pG5q6H3FadR6zmeNBTo?si=48d2b7228a754dc0).

## Version: v3.2.2

Cordelia: current tempo submodule at `a7ecd35a` (branch `devs-iris`).

## Docs

Online docs at DEVELOP: (https://github.com/mskcc/tempo/blob/develop/README.md) or
MASTER: (https://cmotempo.netlify.app/).

## Install

- Make sure to clone with `--recurse-submodules`.

- See `docs/install.md` for more info. Specifically need to install nextflow in `bin`.

## Resume

The run scripts do not resume an earlier run. Each run gets a new UUID and
runs Nextflow in its own scratch folder,
`/scratch/core001/bic/socci/Adagio/<UUID>/run`, so running the script again
starts a new run in a new folder.

To resume a run on IRIS:

1. Find the run folder. It is the `WORKDIR:` line of
   `out/<PROJECT_ID>/runlog/cmd.sh.log`, which is written when Nextflow
   exits. If the driver job was killed first, look for the newest folder
   under `/scratch/core001/bic/socci/Adagio/` whose
   `<PROJECT_ID>_runTempo*.log` names this project.
2. Set the environment the run script sets:

   ```
   export NXF_OPTS='-Xms1g -Xmx4g'
   export NXF_SINGULARITY_CACHEDIR=/scratch/core001/bic/socci/opt/singularity/cachedir
   export TMPDIR=/scratch/core001/bic/socci/Adagio/<UUID>
   export PATH=<adagio>/bin:$PATH
   unset SBATCH_QOS
   ```

3. `cd` to the run folder and run the `nextflow run ... -resume` command
   from `cmd.sh.log` (or from `.nextflow.log` in the run folder).

A manual resume skips the steps the run script does after Nextflow: it
does not copy the mapping and pairing files to `out/<PROJECT_ID>/runlog`,
run `nfTraceReport.R`, or rewrite `cmd.sh.log`.

The trace, report and timeline files are named by date under
`out/<PROJECT_ID>/pipeline_info/`, so earlier ones do not need to be moved.
