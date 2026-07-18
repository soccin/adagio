# IRIS cluster — SLURM reference

**Verified: 2026-07-18. Account: `core001`. User: `soccin`.**

> **This information is a snapshot and WILL go stale.** Partition membership,
> time limits, node counts, and account permissions are changed by the HPC
> sysadmins without notice. Every fact below was verified empirically on the
> date above. **Re-verify before trusting it** — see section 8 for the exact
> commands. If the date above is more than a month old, treat this file as a
> starting hypothesis, not fact.

Scope: what account `core001` can actually submit to, and the limits that bind.
Written for the Adagio/Tempo pipeline but applicable to any batch work on IRIS.

---

## 1. Basics

- **Scheduler: SLURM.** (The older JUNO cluster is LSF — assumptions do not
  transfer between them.)
- **Default account: `core001`.** Available QoS: `normal`, `priority`.
- Access is **not** determined by `AllowGroups`. `AllowGroups=ALL` appears on
  partitions you cannot use. What actually governs access is
  `AllowAccounts` / `DenyAccounts` plus your SLURM associations. Always verify
  by test-submitting (section 8), never by reading `AllowGroups`.

---

## 2. Partitions you can use

Verified 2026-07-18 by `sbatch --test-only` as account `core001`.

| Partition | Max time | Nodes | CPUs/node | Mem/node | Notes |
|---|---|---|---|---|---|
| `cpushort` | **2 h** | **233** | **52 max** | **~975 GB max** | general pool, QoS `cpushort_qos` |
| `cmobic_short` | **3 h** | **37** | 56 | ~1007 GB | group hardware |
| `cmobic_cpu` | **7 d** | **19** | 56 | ~1007 GB | group hardware, long jobs |
| `bic_devs` | 30 d | 1 | 56 | ~1007 GB | dev box only, not for batch |

`cpushort` and `cmobic_short` node sets are **disjoint** (verified by expanding
both to hostnames: 233 + 37, overlap 0). A job that can run in <= 2 h and names
both partitions can therefore land on **270 distinct nodes**.

`cmobic_cpu`'s 19 nodes (`isca[227-240]`, `isco[001-004,006]`) are group-owned
hardware, a subset of the same physical pool as `cmobic_short`.

### Partitions that exist but are not usable for CPU batch work

`gpu`, `bic_gpu` (submission rejected unless you request a GPU),
`interactive` (1 day cap, long queue waits, not for batch),
`datatransfer` (hard-limited to 1 CPU).

### Partitions `core001` is denied

`cpu`, `cpu_highmem`, `preemptable`, `componc_cpu`, `xeon_test`, and all
per-PI partitions. These return
`Invalid account or account/partition combination specified`.

---

## 3. The central constraint: the 2-hour door

`cpu` (238 nodes, 7 days) and `cpushort` (233 nodes, 2 hours) are **the same
physical machines**. Account `core001` is named explicitly in `DenyAccounts` on
`cpu` — and the denial is on the *partition*, not the duration. A 2-hour request
to `cpu` is rejected just as a 4-hour one is.

**So: you may use the entire general pool, but only through the 2-hour door.**
Anything longer must run on your group's own 37 nodes.

This produces three capacity cliffs:

| Job needs | Partition(s) | Reachable nodes | vs. 2 h |
|---|---|---|---|
| <= 2 h | `cpushort,cmobic_short` | **270** | — |
| 2–3 h | `cmobic_short` only | **37** | 7.3x drop |
| > 3 h | `cmobic_cpu` | **19** | 14x drop |

**Practical consequence:** keeping jobs under 2 h is worth real effort. A job
that creeps past 2 h loses 86% of its available hardware; past 3 h, 93%. On a
pipeline with thousands of tasks this is the difference between finishing and
not.

---

## 4. Hard caps that silently reject jobs

These fail at submit time with errors that do **not** explain the real cause.

| Limit | Value | Failure message if exceeded |
|---|---|---|
| `cpushort` CPUs per node | **52** (nodes have 56) | `Requested node configuration is not available` |
| `cpushort` memory per node | **~975 GB** (998557 MB) | `Memory required by task is not available` |
| `cmobic_short` / `cmobic_cpu` | 56 CPUs, ~1007 GB | — |

**The 52-CPU cap on `cpushort` is a trap.** Nodes have 56 cores but the
partition only allows 52. A request for 53–56 CPUs is not an error you will
easily diagnose — it just becomes unschedulable on 233 of your 270 nodes.

Keep per-task CPU requests **<= 52** for anything intended to run on `cpushort`.

### Multi-partition time validation

SLURM validates the requested walltime against the **most restrictive**
partition named. Verified:

```
-p cpushort,cmobic_short -t 02:00:00   -> OK
-p cpushort,cmobic_short -t 03:00:00   -> REJECTED (cpushort caps at 2 h)
-p cmobic_short          -t 03:00:00   -> OK
```

So a 3-hour tier must name **`cmobic_short` alone**. Listing `cpushort`
alongside it silently caps you back to 2 hours.

---

## 5. QoS limits

`cpushort_qos` caps **per user** at `cpu=3068, mem=58T`. No `MaxJobsPU`,
no `MaxSubmitPU`, and no association-level limits on `core001`.

In practice this is generous: at 160 GB per task the memory cap allows ~370
concurrent jobs; at 2 CPUs per task the CPU cap allows ~1500. Neither binds for
a typical pipeline. It can bind if many tasks each request 246 GB or more.

---

## 6. Diagnosing why a job died

If your job wrapper installs a `USR2`/`TERM` trap whose handler exits non-zero
(as Adagio's `conf/iris.config` does, via `catch_term`), then **the exit code
tells you which resource to raise**:

| Cause | Exit code | Signature in the log |
|---|---|---|
| Walltime kill | **1** | `caught USR2/TERM signal` |
| OOM kill | **137** | `... Killed ...` plus `Detected 1 oom_kill event in StepId=...` |

Authoritative confirmation comes from accounting:

```bash
sacct -j <jobid> --format=JobID,State,ExitCode,Elapsed,Timelimit,ReqMem,MaxRSS,AllocCPUS,Partition
```

`State=OUT_OF_MEMORY` versus `State=TIMEOUT` is definitive. A `MaxRSS` that
lands exactly on `ReqMem` means the job was **capped**, not that it peaked
naturally — you have not measured its real requirement, only your own limit.

Caveat: exit 1 is ambiguous in principle, since a genuine program error also
exits 1. Pair it with "runtime near the limit" before concluding walltime.

---

## 7. Transient failures — plan for them

IRIS is a busy shared cluster. **Jobs fail for reasons unrelated to the job.**
A node gets overloaded — by your own pipeline or by other users — and a task
dies within seconds or minutes. This is an infrastructure event and says nothing
about the job's resource requirements.

Rules for any retry logic:

- A task that dies **fast** (seconds to minutes, far short of its limit) should
  be retried with **identical resources in the same partition**. Do not raise
  time. Do not change partition. Conclude nothing.
- Only escalate on **evidence**: raise memory on a real OOM (exit 137), raise
  time on a real walltime kill at the current tier.
- Never promote to the long queue on suspicion. "This tool is usually slow" is
  not evidence. Given the 14x capacity cliff, a wrong promotion is expensive.
- **Budget retries for this.** If transient retries and resource escalation
  share one attempt counter, two unlucky node failures can exhaust the budget
  before the job ever gets one fair run.

---

## 8. How to re-verify everything here

Run these when the date at the top looks old, or when something behaves
unexpectedly.

```bash
# Partitions, time limits, node counts
sinfo -h -o "%P|%l|%D" | sort -u

# Full access-control fields for one partition (note Deny/AllowAccounts)
scontrol show partition cpushort

# Your accounts and QoS
sacctmgr -n -P show assoc user=$USER format=Cluster,Account,Partition,QOS

# THE definitive access test - validates without submitting anything
sbatch --test-only -A core001 -p cpushort -t 02:00:00 -c 4 --mem 16G --wrap="true"
#   "Job N to start at ..."                          -> you can submit
#   "Invalid account or account/partition ..."        -> no access
#   anything else                                     -> policy/limit rejection

# Confirm node-set overlap between two partitions
comm -12 \
  <(scontrol show hostnames $(scontrol show partition cpushort     | tr ' ' '\n' | grep '^Nodes=' | sed 's/Nodes=//') | sort) \
  <(scontrol show hostnames $(scontrol show partition cmobic_short | tr ' ' '\n' | grep '^Nodes=' | sed 's/Nodes=//') | sort) | wc -l

# Current free capacity
sinfo -p cpushort -h -o "%D %t"
```

`sbatch --test-only` **does not submit a job.** It validates the request against
current limits and reports a hypothetical start time. It is safe to run
repeatedly, and it is the only reliable way to answer "can I actually use this
partition" — reading `AllowGroups` will mislead you.

---

## 9. Change log

| Date | Change |
|---|---|
| 2026-07-18 | Initial version. All facts verified this date via `sinfo`, `scontrol`, `sacctmgr`, and `sbatch --test-only`. |
