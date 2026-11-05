# isimipgloballerwq

Water-quality runs of the ISIMIP global lakes with LakeEnsemblR.WQ.
The physical (LakeEnsemblR) set-up uses functions and lake metadata copied
from ISIMIPglobalLER, so that package is not needed. WQ conversion, runs and
ISIMIP output come from LakeEnsemblR.WQ.

## Layout

- `templates/`: `LakeEnsemblR.yaml`, `LakeEnsemblR_WQ.yaml`, `Output.yaml`
  (copied into each lake folder)
- `R/`: project functions, sourced by `scripts/00_settings.R`
  - `setup_ler_lakes.R`: writes the LakeEnsemblR set-up for a set of lakes
  - `wq_helpers.R`: copy WQ templates, run per lake with error logging;
    `run_global_lake()` for the global runs
  - `generic_inflow.R`: generic inflow with constant nutrient
    concentrations; `make_inflow_table()` (residence time and scenario set
    per lake)
  - `trophic_setup.R`: inflow concentrations of the nutrient scenarios
  - `compare_models.R`: read the ISIMIP files at the lakes
    (`read_isimip_lakes()`), statistics per model against the ensemble mean
    (`summarise_model_comparison()`) and time series plots
    (`plot_model_comparison()`, needs ggplot2)
  - `isimip_setup/`: functions copied from ISIMIPglobalLER (commit
    `a8d9608`, author Johannes Feldbauer, GPL >= 3); each file says what
    was changed
- `data/lake_meta_dat.rda`: lake metadata from ISIMIPglobalLER
- `scripts/`: run in order, from the project root
  1. `01_inflow_table.R` (once): writes `data/inflow_table.csv`
  2. `02_run_lakes.R <task>` (HPC array, `hpc/run_lakes.sh`): physical
     set-up, WQ set-up, run and `metrics.rds` for one block of lakes
  3. `03_isimip_output.R <set> <model>` (`hpc/isimip_output.sh`, after
     step 2): `create_isimip_global()` from the saved metrics
- `scripts/example_synthetic.R`: full workflow on synthetic forcing for
  two lakes (2001-2002); writes to `example_run/`. Run it first to check
  the installation.
- `runs/`, `isimip_global/`, `logs/`: generated, not tracked

All paths, climate forcing, lakes and models are set in `scripts/00_settings.R`.

## Global runs

Current climate (`gswp3-era5`, `obsclim`, `histsoc`), all 41449 lakes, with
the same initial conditions (`initial_pars/`) everywhere and the first 10
forcing years repeated once as spin-up. Three sets, written as
`sens_scenario` in the ISIMIP file names
(`glm-aed_gswp3-era5_obsclim_histsoc_<set>_chl_global_daily_1981_1990.nc`):

| Set | Lakes | Inflow |
|---|---|---|
| `lownutr` | with HydroLAKES discharge (40032) | generic, low concentrations |
| `highnutr` | same lakes | generic, high concentrations |
| `default` | `Res_time` -1 (no discharge, 1310) or missing (107) | none |

The inflow equals the outflow and is set from the HydroLAKES residence time
and the hypsograph volume; residence times are clamped to 7 d - 100 yr
(flags `short`/`long` in `data/inflow_table.csv`). A lake is in either the
nutrient sets or `default`, so at each grid cell one of them is 1e20.

Each lake run keeps only `metrics.rds`: the metrics in
`templates/Output_global.yaml` (temperature, DO, TN, TP, total Chl-a,
zooplankton C) as daily epilimnion/hypolimnion means
(`cal_metrics(layers = "epi_hypo")`), about 4 MB per 20 simulated years.
Step 3 writes the ISIMIP variables `watertemp`, `do`, `tp`, `tn`, `chl` and
`zoobio`.

GOTM-WET fails with polar day/night, so lakes beyond the polar circle
(6832, all north of 66.5°N) are run in GOTM-WET at latitude 66.5
(`wet_max_lat`); the other models use the real latitude.

Packages: `layers = "epi_hypo"` and `watertemp` need the current
LakeEnsemblR.WQ; the Simstrat inflow needs LakeEnsemblR with the
`format_flow_simstrat()` fix (inflow temperature and concentrations times
discharge). Older installs fail or give a wrong Simstrat inflow.

On the HPC: set `ISIMIP_FORCING_DIR` and `ISIMIP_HYPSO_NC` (environment
variables, or edit `forcing_dir`/`hypso_nc`), run
step 1, then submit step 2 in chunks (see `hpc/run_lakes.sh`; 10 lakes per
task) and, when it is done, `sbatch hpc/isimip_output.sh`. Failed lakes are
listed in `runs/<climate>/<forcing>/logs/task_*.csv`; resubmitting a task
reruns only the lakes without `metrics.rds`. Test first with a few lakes:
`LAKE_ROWS=26852,26164 Rscript scripts/02_run_lakes.R`, or in parallel on
a multi-core computer, one lake per process:
`Rscript scripts/run_local.R 30 26852 26164 34618`.

## Notes

- `templates/LakeEnsemblR.yaml` started from the LakeEnsemblR.WQ example.
  In- and outflows are off. Name, location, depth, dates, `Kw`, GOTM `nlev`
  and Simstrat `Grid` are set per lake. GLM `bsn_len`/`bsn_wid` are not in
  the template, so LakeEnsemblR computes them from the hypsograph surface
  area A0 (`bsn_wid = sqrt(2*A0/pi)`, `bsn_len = 2*bsn_wid`).
- The simulation stops on 31 December of the last forcing year.
- ISIMIP output years are passed explicitly, because `add_spin_up()` moves
  the yaml start date back by the spin-up years.
- The forcing is read over the lakes' bounding box in blocks of time steps
  (`read_cells()`), because ISIMIP files are chunked per global time step
  and reading cell by cell decompresses the whole file for every lake.
