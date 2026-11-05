# Example: Danish lake with the 1991-2000 forcing repeated twice
#
# Same set-up as example_denmark.R, but with a 10-year spin-up made by
# add_spin_up(): the 1991-2000 forcing is copied to 1981-1990, so the run is
# 1981-2000 with identical forcing in both decades. Comparing the two decades
# shows how far each model is from equilibrium after the first 10 years.
# Writes to example_dnk_spinup/ (not tracked by git).
#
# Run from the project root.

source("scripts/00_settings.R")
source("R/compare_models.R")

dnk_forcing <- "example_climate"
ex_dir <- "example_dnk_spinup"
unlink(ex_dir, recursive = TRUE)
dir.create(ex_dir)

spin_up <- 10   # years; repeats the whole 1991-2000 forcing once

# ---- Lakes ----------------------------------------------------------------
met_paths <- create_cdata_paths(dnk_forcing)
ex_ids <- c(26164)
lake_meta_dat[ex_ids, c("id", "lat", "lon", "depth", "area", "elevation")]

# ---- 1. LakeEnsemblR set-up --------------------------------------------------
ex_dirs <- setup_ler_lakes(lake_id       = ex_ids,
                           lake_meta     = lake_meta_dat,
                           config_file   = file.path(template_dir, "LakeEnsemblR.yaml"),
                           out_path      = file.path(ex_dir, "runs"),
                           nc_files_met  = met_paths,
                           nc_file_hypso = hypso_nc,
                           models        = ler_models,
                           spin_up_years = spin_up)

# ---- 2. WQ set-up ----------------------------------------------------------
copy_wq_templates(ex_dirs, template_dir)
# inflow dates are taken from meteo.csv, so they include the spin-up
for (d in ex_dirs) add_generic_inflow(d, residence_time_d = 365)
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

# Both decades are written (1981-1990 = spin-up, 1991-2000 = after spin-up)
ex_files <- create_isimip_global(ex_lakes,
                                 model      = isimip_models,
                                 start_year = 1991 - spin_up,
                                 end_year   = 2000,
                                 out_dir    = file.path(ex_dir, "isimip_global"),
                                 isimip     = modifyList(isimip_info,
                                                         list(forcing = "gswp3-era5",
                                                              climate_scenario = "obsclim",
                                                              time_ref = "1901-01-01")))
basename(ex_files)

# ---- 5. Spin-up vs. after spin-up ------------------------------------------
cmp <- read_isimip_lakes(file.path(ex_dir, "isimip_global"), ex_lakes)
cmp$cycle <- ifelse(year(cmp$date) < 1991, "spin-up", "after spin-up")

# Whole run: look for trends in the first decade that level off in the second
plot_model_comparison(cmp, lake = ex_lakes$id[1]) +
  ggplot2::geom_vline(xintercept = as.Date("1991-01-01"), linetype = "dashed")

# Same forcing year on top of each other (spin-up shifted forward 10 years)
cmp_overlay <- cmp |>
  filter(!is.na(value)) |>
  mutate(date = if_else(cycle == "spin-up", date + years(spin_up), date))
ggplot2::ggplot(cmp_overlay, ggplot2::aes(x = date, y = value, colour = cycle)) +
  ggplot2::geom_line(linewidth = 0.3) +
  ggplot2::facet_grid(paste(var, level) ~ model, scales = "free_y") +
  ggplot2::labs(x = NULL, y = NULL, colour = NULL, title = ex_lakes$id[1]) +
  ggplot2::theme_bw()

# Annual means: years where the two cycles still differ are not spun up
drift <- cmp |>
  filter(!is.na(value)) |>
  mutate(forcing_year = year(date) + ifelse(cycle == "spin-up", spin_up, 0)) |>
  group_by(model, var, level, forcing_year, cycle) |>
  summarise(mean = mean(value), .groups = "drop") |>
  pivot_wider(names_from = cycle, values_from = mean) |>
  mutate(rel_diff = (`after spin-up` - `spin-up`) / abs(`after spin-up`))
drift |>
  filter(forcing_year %in% c(1991, 2000)) |>
  arrange(model, var, level, forcing_year) |>
  print(n = Inf)

cmp <- cmp |>
  mutate(value = case_when(var == "tn" ~ value * 14.007,
                           var == "tp" ~ value * 30.974,
                           TRUE ~ value),
         units = if_else(var %in% c("tn", "tp"), "mg L-1", units))
