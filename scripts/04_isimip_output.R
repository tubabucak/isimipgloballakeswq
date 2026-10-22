# Step 4: write the ISIMIP lakes_global NetCDF files

source("scripts/00_settings.R")

lakes <- data.frame(id     = paste0("lake_", lake_ids),
                    lat    = lake_meta_dat$lat[lake_ids],
                    lon    = lake_meta_dat$lon[lake_ids],
                    folder = lake_dirs)

# Only lakes whose WQ run succeeded
run_log_file <- file.path(run_dir, "log_run_wq.csv")
if (file.exists(run_log_file)) {
  run_log <- read.csv(run_log_file)
  lakes <- lakes[lakes$folder %in% run_log$folder[run_log$ok], ]
}

# start_year/end_year are given explicitly: the yaml start includes spin-up
create_isimip_global(lakes,
                     model      = isimip_models,
                     start_year = sim_years[1],
                     end_year   = sim_years[2],
                     out_dir    = out_dir,
                     isimip     = isimip_info)
