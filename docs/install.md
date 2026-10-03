# Installation

## Nextflow

Nextflow is pinned to 25.10.4. The IRIS retry logic uses
`task.previousTrace.realtime`, so do not move past 25.x without testing it.
From the adagio folder:

```
bash 00.SETUP.sh
```

or by hand:

```
cd adagio/bin
export NXF_VER=25.10.4
curl -s https://get.nextflow.io | bash
```

## Tempo

Currently using a fork of [Tempo](http://github.com/mskcc/tempo), branch
`devs-iris`. You can find that here:

```
git clone https://github.com/soccin/tempo
```

But if you cloned with `--recurse-submodules` then you do not need to clone it separately.
