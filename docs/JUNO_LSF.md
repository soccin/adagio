# JUNO cluster — LSF reference

**Written: 2026-07-18. Derived from the repo configs only.**

> **Scope warning — this file is weaker than `IRIS_SLURM.md`.** Everything below
> was read out of the checked-in Nextflow configs, which is authoritative for
> *what the pipeline requests*. **Nothing was verified against a live JUNO
> scheduler** — no `bqueues`, `lshosts`, or `bsub` check was run. Queue names,
> node counts, and cluster-side limits are therefore **not documented here**.
> See section 6 before adding any.

Scope: how Adagio drives LSF on JUNO, and the ways it differs from IRIS.

---

## 1. Basics

- **Scheduler: LSF.** IRIS is SLURM. Assumptions do not transfer — see
  `IRIS_SLURM.md`.
- Cluster is detected by `bin/getClusterName.sh`, which sets `$CLUSTER` from
  `CDC_JOINED_ZONE`, falling back to subnet detection (`10.0` -> JUNO).
- The run scripts then select `-profile juno` and the `juno` config files.

---

## 2. Config layering

JUNO settings come from **three** layers, each overriding the last:

| Order | File | Provides |
|---|---|---|
| 1 | `tempo/conf/juno.config` (via `-profile juno`) | Tempo's own defaults: executor, process defaults, wall-time params, reference paths |
| 2 | `conf/juno.config` | Adagio's cluster overrides |
| 3 | `conf/tempo-{wgs,wes}-juno.config` | Per-process cpus / memory / time |

Note this is one layer more than the two `-c` files named in `CLAUDE.md` — the
profile supplies the defaults that the `-c` files then override.

### Layer 1 — `tempo/conf/juno.config`

```groovy
executor { name = "lsf"; queueSize = 5000000000; perJobMemLimit = true }

process {
  memory       = "8.GB"
  time         = { task.attempt < 3 ? 3.h * task.attempt : 500.h }
  scratch      = true
  maxRetries   = 3
  errorStrategy = { task.attempt <= process.maxRetries ? 'retry' : 'ignore' }
  beforeScript = "module load singularity/3.1.1; unset R_LIBS; catch_term () {...}; trap catch_term USR2 TERM"
}

params {
  max_memory   = "128.GB"
  mem_per_core = true
  minWallTime  = 3.h
  medWallTime  = 6.h
  maxWallTime  = 500.h
  wallTimeExitCode = '140,0,1,143'
  reference_base   = "/juno/work/tempo/cmopipeline"
}
```

### Layer 2 — `conf/juno.config`

```groovy
executor { name = "lsf"; queueSize = 2500; perJobMemLimit = true }
process  { clusterOptions = "-R 'cmorsc1'" }
```

`queueSize` is cut from the profile's effective-infinite value to **2500**, and
`clusterOptions` adds the `cmorsc1` host-resource requirement. **No queue is
named anywhere** — jobs go to the LSF default queue.

---

## 3. The resource model: `mem_per_core = true`

**This is the most important JUNO/IRIS difference and the easiest one to get
wrong when porting settings.**

| | JUNO | IRIS |
|---|---|---|
| `mem_per_core` | **`true`** | **`false`** |
| `memory = { 10.GB }` with `cpus = 4` means | 10 GB **per core** = 40 GB total | 10 GB **total** |

`perJobMemLimit = true` in the executor block is what makes LSF interpret the
request per job while the memory figure itself is per core.

The consequence shows up in `conf/tempo-wgs-juno.config`, which deliberately
scales **CPUs** rather than memory on retry — see the comment at
`SomaticDellyCall` / `RunSvABA`:

```groovy
withName: '.*RunSvABA' {
  cpus   = { 8 * task.attempt }   // scaling cpus also scales total memory
  memory = { 4.GB }               // ... because memory is per-core
}
```

On JUNO that retry ramp raises total memory as a side effect. **Copy that idiom
to IRIS and the memory never grows at all** — you get more CPUs and the same
total RAM, which is exactly wrong for an OOM.

---

## 4. Time limits — flat and generous

JUNO has **no queue tiering and no meaningful walltime pressure.** The configs
reflect that:

- Profile default: `task.attempt < 3 ? 3.h * task.attempt : 500.h`.
- `conf/tempo-wgs-juno.config` uses `time = { 500.h }` outright in several
  blocks (`RunMsiSensor`, `RunLOHHLA`, `GermlineDellyCall`, `GermlineRunManta`),
  and ramps to 500 h elsewhere:
  - `SomaticDellyCall`: `task.attempt < 2 ? 100.h : 500.h`
  - `RunSvABA`: `task.attempt < 3 ? 30.h * task.attempt : 500.h`
  - `runBRASS`: `task.attempt < 3 ? 10.h * task.attempt : 500.h`
  - many others: `task.attempt < 2 ? 6.h : 500.h`
- The `meta.size > 100 ? maxWallTime : minWallTime` alignment processes resolve
  to **500 h / 3 h** on JUNO (vs `maxWallTime = 167.h` on IRIS).

**A 500 h request is unremarkable on JUNO and catastrophic on IRIS**, where it
forces the job onto the 19-node `cmobic_cpu` partition. See section 5.

---

## 5. Do not port JUNO settings to IRIS

Three specific traps, all of which look harmless in a diff:

1. **Time.** JUNO's flat `500.h` maps to IRIS's longest and smallest partition.
   IRIS wants the *shortest* tier that works, to stay under the 2-hour door.
2. **Memory.** `mem_per_core` flips from `true` to `false`. A per-core figure
   read as a per-job figure silently under-requests by a factor of `cpus`.
3. **Retries.** JUNO allows `maxRetries = 3`; IRIS's `conf/iris.config` sets
   **2**. A ramp written for three attempts gets truncated.

Also JUNO-only and meaningless on IRIS: `clusterOptions = "-R 'cmorsc1'"`,
`module load singularity/3.1.1`, and `scratch = true` (IRIS sets `scratch =
false` because `true` used `/tmp` even with `TMPDIR` set correctly).

---

## 6. What is NOT documented here, and how to add it

Deliberately absent, because it could not be verified from this session:

- Queue names, per-queue time limits, node counts, host groups.
- What the `cmorsc1` resource actually selects, and how many hosts carry it.
- Whether the default queue is appropriate for multi-day work.
- Whether JUNO is still in active service at all.

**Do not fill these in from memory or by analogy with IRIS.** From a JUNO login
node, the LSF equivalents of the IRIS verification commands are:

```bash
bqueues -l                      # queues, time limits, per-user caps
bhosts -R "cmorsc1"             # hosts carrying the cmorsc1 resource
lshosts -R "cmorsc1"            # their CPU / memory configuration
bmgroup                         # host groups
lsid                            # cluster identity, confirms you are on JUNO
bsub -R "cmorsc1" -W 60 -Is /bin/true   # smallest real submission test
```

LSF has no exact `sbatch --test-only` equivalent, so the last line actually
submits. Keep it tiny and interactive.

Record findings here with a date, and mirror any hard constraint into the
`CLAUDE.md` cluster section only if an agent could break something by not
knowing it.

---

## 7. Change log

| Date | Change |
|---|---|
| 2026-07-18 | Initial version. Config-derived only; no live JUNO scheduler was queried. |
