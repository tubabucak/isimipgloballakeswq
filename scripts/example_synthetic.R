# Example: full workflow for two lakes with synthetic meteo forcing
#
# Uses the real ISIMIP hypsography (`hypso_nc` in 00_settings.R) and writes
# synthetic ISIMIP-style meteo forcing for 2001-2002 on the global 0.5 degree
# grid (only the two lakes' cells hold data). Then runs all steps:
#   1. setup_ler_lakes()        LakeEnsemblR set-up
#   2. export_config_wq()       WQ conversion
#   3. run_ensemble_wq()        model runs
#   4. create_isimip_global()   ISIMIP netcdf files
#
# Run from the project root. Everything is written to example_run/
# (not tracked by git). Takes a few minutes.

source("scripts/00_settings.R")

ex_dir <- "example_run"
unlink(ex_dir, recursive = TRUE)
dir.create(ex_dir)

# ---- Lakes ----------------------------------------------------------------
ex_ids <- c(1, 5)                     # rows of lake_meta_dat
lake_meta_dat[ex_ids, c("id", "lat", "lon", "depth", "area", "elevation")]

# ---- Synthetic meteo forcing (ISIMIP names and units) ----------------------
forcing_ex <- file.path(ex_dir, "climate")
met_dir <- file.path(forcing_ex, "historical", "example-gcm")
dir.create(met_dir, recursive = TRUE)

days <- seq(as.Date("2001-01-01"), as.Date("2002-12-31"), by = "day")
season <- sin(2 * pi * (as.numeric(format(days, "%j")) - 110) / 365)
set.seed(1)
noise <- function(sd) rnorm(length(days), 0, sd)
tas <- 283 + 10 * season + noise(2)                       # K
met_vals <- list(
  tas     = tas,
  hurs    = pmin(100, 75 + noise(8)),                     # %
  sfcwind = pmax(0.5, 4 + noise(1.5)),                    # m s-1
  rlds    = 300 + 40 * season + noise(15),                # W m-2
  rsds    = pmax(10, 150 + 110 * season + noise(30)),     # W m-2
  pr      = pmax(0, 2 + noise(2)) / 86400,                # kg m-2 s-1
  prsn    = ifelse(tas < 273.15, pmax(0, 2 + noise(2)), 0) / 86400,
  ps      = 101000 + noise(500)                           # Pa
)

# Global 0.5 degree grid as in the ISIMIP files; chunked per cell, so the
# files stay small when only the lakes' cells are written
per <- "2001_2002"
dims <- list(ncdim_def("lon", "degrees_east", seq(-179.75, 179.75, by = 0.5)),
             ncdim_def("lat", "degrees_north", seq(89.75, -89.75, by = -0.5)),
             ncdim_def("time", "days since 1850-01-01 00:00:00",
                       as.numeric(days - as.Date("1850-01-01"))))
for (v in names(met_vals)) {
  var <- ncvar_def(v, "", dims, 1e20, prec = "float",
                   chunksizes = c(1, 1, length(days)), compression = 1)
  f <- file.path(met_dir, paste0("example-gcm_r1i1p1f1_w5e5_historical_", v,
                                 "_global_daily_", per, ".nc"))
  nc <- nc_create(f, var, force_v4 = TRUE)
  for (i in ex_ids) {   # same series for both lakes
    ncvar_put(nc, var, met_vals[[v]],
              start = c(lake_meta_dat$x_id[i], lake_meta_dat$y_id[i], 1),
              count = c(1, 1, -1))
  }
  nc_close(nc)
}

# ---- 1. LakeEnsemblR set-up --------------------------------------------------
ex_run_dir <- file.path(ex_dir, "runs")
met_paths <- create_cdata_paths(forcing_ex, "historical", "example-gcm")

ex_dirs <- setup_ler_lakes(lake_id       = ex_ids,
                           lake_meta     = lake_meta_dat,
                           config_file   = file.path(template_dir, "LakeEnsemblR.yaml"),
                           out_path      = ex_run_dir,
                           nc_files_met  = met_paths,
                           nc_file_hypso = hypso_nc,
                           models        = ler_models,
                           spin_up_years = 1)

# ---- 2. WQ set-up ----------------------------------------------------------
copy_wq_templates(ex_dirs, template_dir)
setup_log <- for_each_lake(ex_dirs, setup_wq_lake)
setup_log

# ---- 3. Run the WQ models ----------------------------------------------------
run_log <- for_each_lake(ex_dirs, run_wq_lake, models = wq_models)
run_log

# ---- 4. ISIMIP output --------------------------------------------------------
ex_lakes <- data.frame(id     = lake_meta_dat$id[ex_ids],
                       lat    = lake_meta_dat$lat[ex_ids],
                       lon    = lake_meta_dat$lon[ex_ids],
                       folder = ex_dirs)
ex_lakes <- ex_lakes[run_log$ok, ]

ex_files <- create_isimip_global(ex_lakes,
                                 model      = isimip_models,
                                 start_year = 2001,
                                 end_year   = 2002,
                                 out_dir    = file.path(ex_dir, "isimip_global"),
                                 isimip     = modifyList(isimip_info,
                                                         list(forcing = "example-gcm",
                                                              climate_scenario = "historical")))
basename(ex_files)

# ---- Quick look at one output file ---------------------------------------------
if (length(ex_files) > 0) {
  nc <- nc_open(ex_files[1])
  print(nc)
  nc_close(nc)
}
