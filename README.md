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
  - `wq_helpers.R`: copy WQ templates, run per lake with error logging
  - `isimip_setup/`: functions copied from ISIMIPglobalLER (commit
    `a8d9608`, author Johannes Feldbauer, GPL >= 3); each file says what
    was changed
- `data/lake_meta_dat.rda`: lake metadata from ISIMIPglobalLER
- `scripts/`: run in order, from the project root
  1. `01_setup_ler.R`: `setup_ler_lakes()`
  2. `02_setup_wq.R`: copy WQ templates + `export_config_wq()`
  3. `03_run_wq.R`: `run_ensemble_wq()` per lake
  4. `04_isimip_output.R`: `create_isimip_global()`
- `scripts/example_synthetic.R`: full workflow on synthetic forcing for
  two lakes (2001-2002); writes to `example_run/`. Run it first to check
  the installation.
- `runs/`, `isimip_global/`: generated, not tracked

All paths, scenario, GCM, lakes and models are set in `scripts/00_settings.R`.

## Notes

- `templates/LakeEnsemblR.yaml` started from the LakeEnsemblR.WQ example.
  In- and outflows are off. Name, location, depth, dates, `Kw`, GOTM `nlev`
  and Simstrat `Grid` are set per lake. GLM `bsn_len`/`bsn_wid` are not in
  the template, so LakeEnsemblR computes them from the hypsograph surface
  area A0 (`bsn_wid = sqrt(2*A0/pi)`, `bsn_len = 2*bsn_wid`).
- The simulation stops on 31 December of the last forcing year.
- ISIMIP output years are passed explicitly, because `add_spin_up()` moves
  the yaml start date back by the spin-up years.
- With more than one lake, each forcing file is read as a whole global
  field (`extract_var_id()`), which needs several GB of memory for a
  10-year ISIMIP file.
