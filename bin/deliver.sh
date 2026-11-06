#!/bin/bash

SDIR="$( cd "$( dirname "$0" )" && pwd )"
RDIR=$(realpath $SDIR/..)

# All writes to the delivery area run as the service account;
# with -n they are printed instead
BOT_USER=svc_core001_bot01

# Every delivered file and folder gets this group (rsync --chown).
# rsync -a copies the source group, but the service account cannot set
# a group it is not in, such as a user's own group (the files in
# post/reports are made in a folder without setgid), so those files
# got svc_core001_bot01 as their group.
DGROUP=grp_hpc_core001

# Options of every rsync to the delivery area: the group above; every
# folder group-writable with setgid (rsync -a copies the source mode,
# and post/reports is made without them, so the group could not
# delete the files in it); and no macOS metadata files ("._<name>",
# written next to a file opened from a Mac)
RSYNC=(rsync -aP --chown=:"$DGROUP" --chmod=Dg+ws --exclude="._*")

asbot() {
    if [[ "$DRYRUN" -eq 1 ]]; then
        echo "DRYRUN: dzdo -u $BOT_USER ${*@Q}"
    else
        dzdo -u "$BOT_USER" "$@"
    fi
}

# Default delivery path from .../Users/Aa/BBB/Proj_nnnnn/...
# -> aaa/bbb/Proj_nnnnn (first two folders lowercased; project as-is)
CWD=$(pwd)
if [[ "$CWD" != *"/Users/"* ]]; then
    DPATH=""
else
    rest="${CWD#*/Users/}"
    IFS=/ read -r u1 u2 proj _ <<< "$rest"
    if [[ -n "$u1" && -n "$u2" && -n "$proj" ]]; then
        DPATH="$(printf '%s' "$u1" | tr '[:upper:]' '[:lower:]')/$(printf '%s' "$u2" | tr '[:upper:]' '[:lower:]')/$proj"
    else
        DPATH=""
    fi
fi

usage() {
    echo -e "\n   usage: deliver.sh [-n] [-r] /path/to/delivery/folder/r_00x"
    echo -e "          deliver.sh [-n] [-r] -d|--default"
    echo -e "\n   -n, --dry-run         print the delivery and database commands, do"
    echo -e "                         not run them; the email and project.yaml are"
    echo -e "                         still written here"
    echo -e "   -r, --redact-facets   do not deliver the FACETS files; the MAFs,"
    echo -e "                         sample_data.txt, MultiQC and reports keep"
    echo -e "                         their FACETS columns"
    echo -e "\n   default: ${DPATH:-"(none)"}\n"
}

ODIR=""
USE_DEFAULT=0
DRYRUN=0
REDACT_FACETS=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--default)
            USE_DEFAULT=1
            shift
            ;;
        -n|--dry-run)
            DRYRUN=1
            shift
            ;;
        -r|--redact-facets)
            REDACT_FACETS=1
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            ODIR="$1"
            shift
            ;;
    esac
done

DROOT=/data1/core002/res/bic/results

if [[ "$USE_DEFAULT" -eq 1 && -z "$ODIR" ]]; then
    if [[ -z "$DPATH" ]]; then
        echo "Error: no default delivery path for current directory"
        usage
        exit 1
    fi
    ODIR="$DROOT/$DPATH"
fi

if [[ -z "$ODIR" ]]; then
    usage
    exit
fi

# CURRDIR: trailing /r_NNN on ARG1 as-is; else next after latest in ODIR; else r_001
CURRDIR=r_001
if [[ "$ODIR" =~ /r_[0-9]+$ ]]; then
    CURRDIR="${ODIR##*/}"
    ODIR="${ODIR%/*}"
elif [[ -d "$ODIR" ]]; then
    last=$(ls -1 "$ODIR" | grep -E '^r_[0-9]+$' | sort | tail -1)
    if [[ "$last" =~ ^r_([0-9]+)$ ]]; then
        CURRDIR=$(printf 'r_%03d' $((10#${BASH_REMATCH[1]} + 1)))
    fi
fi

echo "ODIR=$ODIR"
echo "CURRDIR=$CURRDIR"
echo "REDACT_FACETS=$REDACT_FACETS"

# -r: skip the FACETS files: the per-pair facets/ folders, Tempo's
# cohort cna_* files (SomaticAggregateFacets), post/plots/facets and
# the *_facets_v5 and *_facetsQCRpt_v1 reports. Files that only carry
# FACETS columns (MAFs, sample_data.txt, MultiQC, SNV and All reports)
# are still delivered.
FACETS_EXCLUDES=()
if [[ "$REDACT_FACETS" -eq 1 ]]; then
    FACETS_EXCLUDES=(--exclude="*facets*" --exclude="cna_*")
fi

asbot mkdir -p "$ODIR/$CURRDIR/tempo"

asbot "${RSYNC[@]}" --exclude="*.ba[mi]" --exclude="*.snp_pileup.gz" --exclude="*germline*" "${FACETS_EXCLUDES[@]}" out/ "$ODIR/$CURRDIR/tempo"
asbot "${RSYNC[@]}" "${FACETS_EXCLUDES[@]}" post "$ODIR/$CURRDIR"

eval $(cat out/*/runlog/cmd.sh.log  | fgrep PROJECT_ID | sed 's/: /=/')
eval $(cat out/*/runlog/cmd.sh.log  | fgrep GTAG: | sed 's/: /=/')
eval $(cat out/*/runlog/cmd.sh.log  | fgrep ASSAY_TYPE: | sed 's/: /=/')

# Doc link points at the release tag the run was built from
if [[ "$GTAG" =~ ^(.+)-[0-9]+-g[0-9a-f]+(-UNCOMMITED)?$ ]]; then
    VERSION="${BASH_REMATCH[1]}"
else
    VERSION="UNKNOWN"
    echo "WARNING: cannot get version from GTAG=$GTAG; fix doc link in email"
fi

if [ -e "Map/sbam" ]; then
  asbot mkdir -p "$ODIR/$CURRDIR/mapping"
  asbot "${RSYNC[@]}" --exclude="*.ba[mi]" Map/sbam/ "$ODIR/$CURRDIR/mapping"
fi

if [ -e "Map/out/metrics" ]; then
  asbot mkdir -p "$ODIR/$CURRDIR/mapping"
  asbot "${RSYNC[@]}" Map/out/metrics "$ODIR/$CURRDIR/mapping"
fi

# Tagged email lines, so the email lists only what was delivered:
# {FACETS} lines are dropped with -r, {WGS} lines are kept only for
# genome runs. The tag is removed from the lines that are kept.
if [[ "$REDACT_FACETS" -eq 1 ]]; then
    FACETS_SED='/^{FACETS}/d'
else
    FACETS_SED='s/^{FACETS}//'
fi
if [[ "$ASSAY_TYPE" == "genome" ]]; then
    WGS_SED='s/^{WGS}//'
else
    WGS_SED='/^{WGS}/d'
    if [[ "$ASSAY_TYPE" != "exome" ]]; then
        echo "WARNING: ASSAY_TYPE=$ASSAY_TYPE in cmd.sh.log; whole-genome reports left out of email"
    fi
fi

echo
echo "========================================================================="
echo
sed -e "$FACETS_SED" \
  -e "$WGS_SED" \
  -e "s/{PROJNO}/$PROJECT_ID/g" \
  -e "s/{RUNDIR}/$CURRDIR/g" \
  -e "s/{VERSION}/$VERSION/g" \
  $RDIR/assets/delivery_email_template.txt \
  | tee deliveryEmail_${PROJECT_ID}_${CURRDIR}_$(date +%y%m%d).txt

BIC_DELIVERY=$HOME/Code/BIC/Delivery/Version2j
Rscript $SDIR/readme2yaml.R adagio $CURRDIR

PERMS=$BIC_DELIVERY/authorization_db/init_impact_project_permissions.py
if [[ "$DRYRUN" -eq 1 ]]; then
    echo "DRYRUN: module load python/3.8.0 py-python-ldap/3.4.2"
    echo "DRYRUN: python3.8 $PERMS -p project.yaml"
    echo
    echo "DRY RUN: would deliver to $ODIR/$CURRDIR; nothing was written there or to the database"
    echo
else
    module purge
    module load python/3.8.0
    PYTHON38=$(which python3.8)
    module load py-python-ldap/3.4.2
    $PYTHON38 "$PERMS" -p project.yaml
fi
