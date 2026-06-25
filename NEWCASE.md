# Creating and running a case

`newcase.sh` scaffolds a ready-to-run MPAS-ESM coupled case from this checkout,
so a new user goes from a built model to a submitted run in a few commands. The
whole workflow is:

```
build  →  newcase  →  populate data/  →  edit submit.sh  →  ./submit.sh
```

---

## 1. Prerequisites

You need a **built** MPAS-ESM checkout — this directory — containing:

- `install/bin/esmx_app` (or `esmx_app_regional`) — the coupled executable
- `envs/derecho_env_intel.sh` — the build environment
- `template/` — the case boilerplate (config, scripts, physics tables)
- `newcase.sh`

If the model isn't built yet, either run `build.sh` or use a pre-built executable.

---

## 2. Create a case

Run `newcase.sh` in this checkout (so it finds the binary and env):

```bash
./newcase.sh CASENAME
```

To also populate the case's `data/` from a data package:

```bash
./newcase.sh CASENAME --data PACKAGE
```

### Options

| Option | Meaning |
|---|---|
| `-d, --data DIR`     | symlink every file in `DIR` into `CASENAME/data/` (else `data/` is left empty) |
| `-a, --app DIR`      | checkout to take the binary + env from (default: current directory) |
| `-b, --bin PATH`     | explicit executable (default: `<app>/install/bin/esmx_app*`) |
| `-t, --template DIR` | boilerplate dir (default: `<script_dir>/template`) |
| `-o, --dest DIR`     | parent dir to create the case in (default: cwd) |
| `-h, --help`         | show help |

> **Run it from your build checkout.** `--app` defaults to the current directory,
> so if you run `newcase` from somewhere without `install/bin/` and `envs/`, the
> binary and env links will be missing. Either `cd` into this checkout first or
> pass `--app /path/to/checkout`.

---

## 3. What a case contains

```
CASENAME/
├── data/                         ← your inputs + the dataset's config (see below)
├── esmxRun.yaml                  ← driver config (PE layout, meshes, clock)
├── fd_cesm.yaml, input.nml       ← driver / FMS config
├── stream_list.atmosphere.*      ← MPAS stream field lists
├── submit.sh                     ← edit and submit job script
├── job_card.derecho.intel        ← PBS job (submit.sh calls qsub on it)
├── clean.sh, collect_metrics.py  ← quality of life scripts
├── *.TBL, *.DBL, RRTMG_*         ← physics tables
├── derecho_env_intel.sh          ← env
└── esmx_app                      ← executable
```

Only **generic** driver config is copied from the template. The
**dataset-coupled** config travels with the data package, not the template:

```
MOM_input  MOM_override  diag_table
namelist.atmosphere  namelist.init_atmosphere
streams.atmosphere   streams.init_atmosphere
```

---

## 4. The `data/` folder

Drop **all** inputs for your run into `data/` — both the data files *and* the
dataset-coupled config listed above. (`--data` does this for you from a package
directory.)

- **Pure inputs** (meshes, grids, ICs, LBCs, OBC forcing, graph) stay in `data/`.
  The config points at them there: `esmxRun.yaml` mesh paths, MPAS
  `filename_template`s, and MOM6 `INPUTDIR = ./data` all read from `data/`.
- **Cwd-pinned config** (`MOM_input`, `namelist.atmosphere`, etc.) must sit at
  the case root at run time, because the model opens them by fixed name from the
  run directory. You don't move them by hand — **`submit.sh` promotes them out of
  `data/` up to the case root automatically** at submit time. If one of those
  files is in neither place, `submit.sh` stops with `file not found: <name>`.

---

## 5. Configure the run — edit `submit.sh`

All per-run settings live in the knobs at the top of `submit.sh`:

| Knob | Meaning |
|---|---|
| `NODES` | Derecho nodes (128 cores each) |
| `ATM_PCT` / `OCN_PCT` | split of cores between ATM and OCN |
| `MED_OVERLAP_OCN` | `true`: mediator shares OCN's PEs; `false`: MED gets `MED_PCT` |
| `START_TIME` / `STOP_TIME` | run window, `YYYY-MM-DDThh:mm:ss` |
| `WALLTIME` | PBS walltime `HH:MM:SS` (or pass as `./submit.sh 02:00:00`) |
| `ATM_MESH` / `OCN_MESH` | mesh filenames in `data/` |

`submit.sh` then, in order: promotes the cwd-pinned config from `data/`; writes
the PE `petList`s, mesh paths, and clock (`startTime`/`stopTime`, derived CMEPS
`stop_n`/`stop_option`, and the MPAS `namelist.atmosphere` dates) into
`esmxRun.yaml`/`namelist.atmosphere`; and submits the job with a matching
`select=`/walltime.

---

## 6. Run

```bash
cd CASENAME
./submit.sh
```

Each run lands in its own subdirectory under `RUNS/`:

```
RUNS/RUN_<DUR>_CLP<couple_freq>/ATM<n>_OCN<n>_MED<n>/
    job.out, job.err, esmxRun.yaml, logs, history/restart, jobid.txt
```

`collect_metrics.py` records timing into `summaries/run_metrics.csv`.

---

## Reference paths

Resources for the Carib 3 km coupled case:

- **Binary** (`esmx_app` build):
  ```
  /glade/u/home/mullis/MPAS-ESM/install/bin/esmx_app_regional
  ```
- **Data package** (full coupled inputs + dataset config):
  ```
  /glade/derecho/scratch/mullis/cpl_carib_3km_data
  ```

Putting it together:

```bash
./newcase.sh CASENAME
    --bin /glade/u/home/mullis/MPAS-ESM/install/bin/esmx_app_regional
    --data /glade/campaign/cesm/mpas_mom6/v0/cpl_carib_3km_data
cd CASENAME
# edit knobs in submit.sh, then:
./submit.sh
```
