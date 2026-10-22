# Example: full workflow for Danish lakes with real ISIMIP forcing
#
# Uses GSWP3-ERA5 obsclim forcing for Denmark, 1991-2000 (files
# *_dnk_30arcmin_daily_1991_2000.nc in example_climate/) and the ISIMIP
# hypsography (`hypso_nc` in 00_settings.R). Runs all steps for a few lakes
# and writes to example_dnk/ (not tracked by git).
#
# Run from the project root.

source("scripts/00_settings.R")
source("R/compare_models.R")

dnk_forcing <- "example_climate"
ex_dir <- "example_dnk"
unlink(ex_dir, recursive = TRUE)
dir.create(ex_dir)

# ---- Lakes ----------------------------------------------------------------
# Danish lakes = lakes whose grid cell has data in the Denmark forcing
met_paths <- create_cdata_paths(dnk_forcing)
nc <- nc_open(met_paths$path[met_paths$var == "at"][1])
tas1 <- ncvar_get(nc, names(nc$var)[1], count = c(-1, -1, 1))
nc_close(nc)
dnk_ids <- which(!is.na(tas1[cbind(lake_meta_dat$x_id, lake_meta_dat$y_id)]))
message(length(dnk_ids), " Danish lakes")

# A few of them: three with a repeated area level in the hypsograph
# (25476, 26164, 26504) and three without (26853, 26165, 25478)
ex_ids <- c(25476, 26164, 26504, 26853, 26165, 25478)
stopifnot(all(ex_ids %in% dnk_ids))
lake_meta_dat[ex_ids, c("id", "lat", "lon", "depth", "area", "elevation")]

# ---- 1. LakeEnsemblR set-up --------------------------------------------------
ex_dirs <- setup_ler_lakes(lake_id       = ex_ids,
                           lake_meta     = lake_meta_dat,
                           config_file   = file.path(template_dir, "LakeEnsemblR.yaml"),
                           out_path      = file.path(ex_dir, "runs"),
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
                                 start_year = 1991,
                                 end_year   = 2000,
                                 out_dir    = file.path(ex_dir, "isimip_global"),
                                 isimip     = modifyList(isimip_info,
                                                         list(forcing = "gswp3-era5",
                                                              climate_scenario = "obsclim",
                                                              time_ref = "1901-01-01")))
basename(ex_files)

# ---- 5. Compare the models ---------------------------------------------------
cmp <- read_isimip_lakes(file.path(ex_dir, "isimip_global"), ex_lakes)
summarise_model_comparison(cmp)
plot_model_comparison(cmp, lake = ex_lakes$id[1])
