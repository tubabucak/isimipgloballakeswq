# isimipgloballerwq

Water-quality runs of the ISIMIP global lakes with LakeEnsemblR.WQ.
The physical (LakeEnsemblR) set-up uses functions and lake metadata copied
from ISIMIPglobalLER (Johannes Feldbauer) and changed if necessary. WQ conversion, runs and
ISIMIP output come from LakeEnsemblR.WQ.

## Layout

- `templates/`: `LakeEnsemblR.yaml`, `LakeEnsemblR_WQ.yaml`, `Output.yaml`
  (copied into each lake folder); `Output_global.yaml` (metrics of the
  global runs)
- `R/`: project functions, sourced by `scripts/00_settings.R`
  - `setup_ler_lakes.R`: writes the LakeEnsemblR set-up for a set of lakes
  - `wq_helpers.R`: copy WQ templates, run per lake with error logging;
    `run_global_lake()` for the global runs
  - `generic_inflow.R`: generic inflow with constant nutrient
    concentrations; `make_inflow_table()` (residence time and scenario set
    per lake)
  - `trophic_setup.R`: inflow concentrations of the nutrient scenarios
  - `compare_models.R`: read the ISIMIP files at the lakes
    (`read_isimip_lakes()`, optionally only some nutrient scenarios),
    statistics per scenario and model against the ensemble mean
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
- `hpc/submit_all.sh`: submits steps 2 and 3 of the global runs at once
- `scripts/example_synthetic.R`: full workflow on synthetic forcing for
  two lakes (2001-2002); writes to `example_run/`. Run it first to check
  the installation.
- `scripts/example_denmark*.R`: tests with Danish lakes and the forcing in
  `example_climate/` (plain, with spin-up, with nutrient states)
- `scripts/run_local.R`: step 2 for a few lakes in parallel on a
  multi-core computer; `scripts/run_denmark_local.ps1`: steps 2 and 3 for
  the 40 Danish lakes on Windows
- `scripts/plot_isimip_test.R`: plots of the ISIMIP files of a test run;
  `scripts/compare_depths.R`: ISIMIP against HydroLAKES mean depths
- `runs/`, `isimip_global/`, `logs/`: generated, not tracked

All paths, climate forcing, lakes and models are set in `scripts/00_settings.R`.
The default paths there are the local example data (`example_climate/`,
`data/hypso_area.nc`); on the HPC they are set with environment variables
(see below).

To leave a WQ model out, comment it out under `models:` in
`templates/LakeEnsemblR_WQ.yaml` and remove it from `wq_models` and
`isimip_models` in `00_settings.R`. `copy_wq_templates()` copies only the
`initial_pars/` rows of the models in `LakeEnsemblR_WQ.yaml`.

## Global runs

Current climate (`gswp3-era5`, `obsclim`, `histsoc`), all 41449 lakes, with
the same initial conditions (`initial_pars/`) everywhere. The run uses the
forcing files from `first_year` (1981, set in `00_settings.R`) to the end of
the forcing; the first 10 of these years are repeated once as spin-up. Two
sets, written as `sens_scenario` in the ISIMIP file names
(`glm-aed_gswp3-era5_obsclim_histsoc_<set>_chl_global_daily_1981_1990.nc`):

| Set | Lakes | Inflow |
|---|---|---|
| `lownutr` | all 41449 | generic, low concentrations |
| `highnutr` | same lakes | generic, high concentrations |

### Inflow

Every lake gets a constant inflow Q equal to the outflow (no water balance),
from the residence time τ and the hypsograph volume V: Q = V / τ. The
nutrient load is Q × C, with constant concentrations C per set
(`trophic_presets` in `R/trophic_setup.R`, chosen in `nutr_scenarios` in
`00_settings.R`). The inflow temperature is the 7-day mean air temperature
(at least 0 °C), and the inflow oxygen is at saturation for that temperature.

τ per lake is in `data/inflow_table.csv` (step 1, `make_inflow_table()`):

| `source` | Lakes | Residence time |
|---|---|---|
| `hydrolakes` | 40032 with HydroLAKES discharge | HydroLAKES `Res_time` |
| `est_wshd` | 1310 with `Res_time` -1 (`Dis_avg` 0: mostly terminal lakes in arid basins) | estimated from the watershed area |
| `est_wshd_assumed` | 107 without HydroLAKES data (-9999: small islands, far Arctic) | estimated from an assumed watershed area |

The discharge of the lakes without it is estimated as follows:

1. Fit log10(`Dis_avg`) = -2.08 + 0.925 × log10(`Wshd_area`) on the lakes
   with discharge (R² 0.78; lake area or volume explain much less, R² 0.34).
2. Lakes without a watershed area get `Lake_area` × the median
   `Wshd_area` / `Lake_area` of the lakes with discharge in the same
   |latitude| band (0-30°: 42, 30-50°: 51, 50-66.5°: 16, > 66.5°: 6.8),
   capped at the global median (24), because on small islands the island
   limits the catchment.
3. Regional correction: the fitted discharge is multiplied by the median
   ratio of HydroLAKES to fitted discharge of the lakes with discharge within
   5° (at least 10 lakes, otherwise no correction). Arid regions thus get
   less water than the global fit gives.
4. τ = `Vol_total` / estimated discharge.

All residence times are clamped to 7 d - 100 yr (`flag` `short`/`long` in
the table; `res_time_hl` is the HydroLAKES value, `res_time_est` the
estimate, `res_time` the value used). With
`make_inflow_table(estimate_missing = FALSE)` the lakes without discharge get
no inflow and are run once as a third set, `default`.

Each lake run keeps only `metrics.rds`: the metrics in
`templates/Output_global.yaml` (temperature, DO, TN, TP, total Chl-a,
zooplankton C) as daily epilimnion/hypolimnion means
(`cal_metrics(layers = "epi_hypo")`), ~ 4 MB per 20 simulated years.
Step 3 writes the ISIMIP variables `watertemp`, `do`, `tp`, `tn`, `chl` and
`zoobio`.

GOTM-WET fails with polar day/night, so lakes beyond the polar circle
(6832, all north of 66.5°N) are run in GOTM-WET at latitude 66.5
(`wet_max_lat`); the other models use the real latitude.


On the HPC (VSC): the job scripts in `hpc/` run on `zen4` with
`--export=NONE` and source `~/env_lerwq.sh`, which loads R and netCDF
(for `nccopy`) and sets the R library; the jobs stop if LakeEnsemblR.WQ is
not found in that library. `ISIMIP_FORCING_DIR` is exported in the job
scripts and `ISIMIP_HYPSO_NC` must be set as well; without them the runs use
the local example data. Step 3 has one array task per set and model
(0-3 `lownutr`, 4-7 `highnutr`, 8-11 `default`); with all lakes in
`lownutr`/`highnutr`, submit it with `--array=0-7`. Run step 1
(`Rscript scripts/01_inflow_table.R`), then `bash hpc/submit_all.sh` from
the project root on the login node: it submits step 2 in chunks of 1000
array tasks (10 lakes per task, at most `MAX_RUNNING` = 200 at once) and
step 3 (`hpc/isimip_output.sh`) to start when step 2 has ended. Step 2 can
also be submitted by hand (see `hpc/run_lakes.sh`). Failed lakes are
listed in `runs/<climate>/<forcing>/logs/task_*.csv`; resubmitting a task
reruns only the lakes without `metrics.rds`. Test first with a few lakes:
`LAKE_ROWS=26852,26164 Rscript scripts/02_run_lakes.R`, or in parallel on
a multi-core computer, one lake per process:
`Rscript scripts/run_local.R 3 26852 26164 34618`.

## Notes

- `templates/LakeEnsemblR.yaml` started from the LakeEnsemblR.WQ example.
  In- and outflows are off there and switched on per lake by
  `add_generic_inflow()`. Name, location, depth, dates, `Kw`, GOTM `nlev`
  and Simstrat `Grid` are set per lake. GLM `bsn_len`/`bsn_wid` are not in
  the template, so LakeEnsemblR computes them from the hypsograph surface
  area A0 (`bsn_wid = sqrt(2*A0/pi)`, `bsn_len = 2*bsn_wid`).
- The simulation stops on 31 December of the last forcing year.
- The climate files store one compressed world map per day, so reading one
  lake still means unpacking the whole map. The forcing is therefore read
  once for all lakes together (the rectangle around them), a group of days
  at a time to limit memory (read_cells()), instead of once per lake.

