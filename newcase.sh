#!/bin/bash
# =============================================================================
# newcase.sh - create a ready-to-run MPAS-ESM case directory.
#
#   ./newcase.sh CASENAME [options]
#
# Makes a folder named CASENAME, populates it with the necessary files
# (config, scripts, physics tables) from a self-contained template, links the
# model binary + env from your MPAS-ESM build, and creates an empty data/ folder
# with a DATA.md describing the inputs the model expects. You drop your input
# files into CASENAME/data/ and the config reads them straight from there
# (esmxRun mesh paths, MPAS streams, and MOM6 INPUTDIR all point at data/)
#
# Config/scripts/tables come from the template; the binary and env
# come from your own build (--app, i.e. your MPAS-ESM checkout, or --bin). You
# supply only your input data in CASENAME/data/ (or --data to populate it from a directory).
#
# Options:
#   -t, --template DIR  canonical boilerplate dir to build from  (alias: -r/--ref)
#                    (default: $DEFAULT_REF, i.e. <script_dir>/template)
#   -a, --app DIR    MPAS-ESM/app checkout for the binary + env
#                    (default: current working directory; run newcase from there,
#                     or pass --app /path/to/checkout)
#   -o, --dest DIR   parent dir to create CASENAME in (default: cwd)
#   -b, --bin PATH   model executable (default: <app>/install/bin/esmx_app* else <ref>/esmx_app)
#   -d, --data DIR   data package to populate CASENAME/data/ from (symlinks every
#                    file in DIR into data/).  Default: leave data/ empty.
#   -h, --help       show this help
# =============================================================================
set -eu

SCRIPTDIR=$(cd "$(dirname "$(readlink -f -n "${BASH_SOURCE[0]}")")" && pwd -P)
DEFAULT_REF="/glade/campaign/cesm/mpas_mom6/v0/template"   # canonical boilerplate (config/scripts/tables); travels with this script
DEFAULT_STATIC="/glade/campaign/cesm/mpas_mom6/v0/static_data"     # physics tables and RRTMG data
DEFAULT_APP="$PWD"   # the MPAS-ESM/app checkout you run newcase from (has install/bin/esmx_app + envs/); override with --app

# ---- what makes up the "necessary" (non-data) case ----------------------------
# Generic driver/model config copied from the template.  The dataset-coupled
# config (MOM_input, MOM_override, diag_table, namelist.atmosphere,
# namelist.init_atmosphere, streams.atmosphere, streams.init_atmosphere) is NOT
# here: it ships with the data package, so you drop it into data/ and submit.sh
# promotes it to the case root at run time.
CONFIG_FILES=(                       # copied from the template
  esmxRun.yaml fd_cesm.yaml input.nml
  stream_list.atmosphere.diagnostics stream_list.atmosphere.diag_ugwp
  stream_list.atmosphere.output stream_list.atmosphere.surface
)
SCRIPT_FILES=( submit.sh job_card.derecho.intel clean.sh collect_metrics.py )  # copied
TABLE_GLOBS=( "*.TBL" "*.DBL" "RRTMG_LW_DATA" "RRTMG_SW_DATA" )                 # symlinked
ENV_FILE="derecho_env_intel.sh"                                                 # symlinked to build env

# ---- parse args ---------------------------------------------------------------
CASENAME=""; REF="$DEFAULT_REF"; APP="$DEFAULT_APP"; DEST="$PWD"; BIN=""; DOC=""; DATA=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) sed -n '2,29p' "$0"; exit 0 ;;
    -t|--template|-r|--ref)  REF="$2";  shift 2 ;;
    -a|--app)  APP="$2";  shift 2 ;;
    -o|--dest) DEST="$2"; shift 2 ;;
    -b|--bin)  BIN="$2";  shift 2 ;;
    -d|--data) DATA="$2"; shift 2 ;;
    --doc)     DOC="$2";  shift 2 ;;
    -*) echo "ERROR: unknown option $1" >&2; exit 1 ;;
    *)  [ -z "$CASENAME" ] && CASENAME="$1" || { echo "ERROR: extra arg $1" >&2; exit 1; }; shift ;;
  esac
done
[ -n "$CASENAME" ] || { echo "ERROR: CASENAME required.  ./newcase.sh CASENAME [options]" >&2; exit 1; }
[ -d "$REF" ] || { echo "ERROR: --ref '$REF' not found." >&2; exit 1; }
[ -n "$DATA" ] && [ ! -d "$DATA" ] && { echo "ERROR: --data '$DATA' not found." >&2; exit 1; }
CASE="$DEST/$CASENAME"
[ -e "$CASE" ] && { echo "ERROR: '$CASE' already exists." >&2; exit 1; }

# ---- resolve binary -----------------------------------------------------------
if [ -z "$BIN" ]; then
  BIN=$(ls -t "$APP"/install/bin/esmx_app_regional "$APP"/install/bin/esmx_app 2>/dev/null | head -1 || true)
  [ -z "$BIN" ] && [ -e "$REF/esmx_app" ] && BIN="$REF/esmx_app"
fi

# ---- build the case -----------------------------------------------------------
echo "Creating case: $CASE"
mkdir -p "$CASE/data"

# data package: symlink every file from DATA into data/ (config files are pulled
# up to the case root later by submit.sh; pure inputs stay here)
if [ -n "$DATA" ]; then
  n=0
  for f in "$DATA"/*; do
    [ -e "$f" ] || continue
    ln -s "$(readlink -f "$f")" "$CASE/data/$(basename "$f")"; n=$((n+1))
  done
  echo "  data/  populated with $n file(s) from $DATA"
fi

for f in "${CONFIG_FILES[@]}" "${SCRIPT_FILES[@]}"; do
  if [ -e "$REF/$f" ]; then cp -r "$REF/$f" "$CASE/"; else echo "  ! missing in ref: $f" >&2; fi
done

if [ -d "$DEFAULT_STATIC" ]; then
  for f in "${DEFAULT_STATIC}"/*; do
    [ -e "$f" ] || continue
    ln -s "$(readlink -f "$f")" "$CASE/$(basename "$f")"
  done
else
  echo "  ! static data dir not found: $DEFAULT_STATIC" >&2
fi

# env: link the canonical build env so run env == build env
if   [ -e "/glade/campaign/cesm/mpas_mom6/v0/template/derecho_env_intel.sh" ]; then ln -s "/glade/campaign/cesm/mpas_mom6/v0/template/derecho_env_intel.sh" "$CASE/$ENV_FILE"
elif [ -e "$REF/$ENV_FILE" ];       then cp -p "$REF/$ENV_FILE" "$CASE/$ENV_FILE"
else echo "  ! no env script ($ENV_FILE) found" >&2; fi

# binary
if [ -n "$BIN" ] && [ -e "$BIN" ]; then ln -s "$(readlink -f "$BIN")" "$CASE/esmx_app"
else echo "  ! no binary found; link one later: ln -s <path> $CASE/esmx_app" >&2; fi

# ---- input documentation (not an enforced checklist) --------------------------
[ -z "$DOC" ] && for c in "$REF/DATA.md" "$SCRIPTDIR/DATA.md"; do [ -e "$c" ] && { DOC="$c"; break; }; done
if [ -n "$DOC" ] && [ -e "$DOC" ]; then cp -p "$DOC" "$CASE/data/DATA.md"
else echo "  ! no DATA.md doc found (see --doc)" >&2; fi

# ---- report -------------------------------------------------------------------
echo "============================================================"
echo " Case   : $CASE"
echo " Binary : ${BIN:-<none - set CASE/esmx_app>}"
echo " Inputs : ${DATA:-<none - put your input files in $CASE/data/>}"
echo "------------------------------------------------------------"
echo " Next:"
echo "   cd $CASE"
echo "   # put your input files in ./data/   (guide: data/DATA.md)"
echo "   # edit knobs in submit.sh, then:  ./submit.sh"
echo "============================================================"
