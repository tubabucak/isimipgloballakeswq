# Example: oligotrophic vs. eutrophic set-up for a Danish lake
#
# Both set-ups use the same model parameters, physics, forcing (1991-2000,
# repeated once as a 10-year spin-up) and HydroLAKES residence time; only the inflow
# nutrient concentrations and the initial water-column nutrients differ (see
# trophic_presets in R/trophic_setup.R). Targets for the in-lake means:
#   oligotrophic: TP ~0.010 mg/L, TN <= 0.35 mg/L
#   eutrophic:    TP  > 0.100 mg/L, TN  > 1.2 mg/L
# Writes to example_dnk_trophic/<state>/ (not tracked by git).
#
# Run from the project root.

source("scripts/00_settings.R")
source("R/compare_models.R")

dnk_forcing <- "example_climate"
ex_dir <- "example_dnk_trophic"
unlink(ex_dir, recursive = TRUE)
dir.create(ex_dir)

spin_up  <- 10
# Rows of lake_meta_dat (max. depth from the ISIMIP hypsograph):
# 26852: reference; 14.6 m, 3.3 km2, residence time ~260 d, hypsograph volume
#        within 10% of HydroLAKES Vol_total (26164 is a run-of-river lake, ~4 d)
# 26503: deepest; 99.9 m, 16.1 km2, ~2100 d (Esrum Soe cell; real max. ~22 m,
#        hypsograph volume 4x HydroLAKES)
# 26167: largest freshwater lake; 37.7 km2, 98.7 m, ~710 d (Arresoe cell; the
#        larger 26161/26497 are coastal fjords at -2 m elevation)
# 26851: small; 0.17 km2, 16.6 m, ~170 d (smaller 25474 is run-of-river, ~6 d)
ex_ids   <- c(26852, 26503, 26167, 26851)
met_paths <- create_cdata_paths(dnk_forcing)
ex_hl    <- get_hydrolakes(ex_ids, lake_meta_dat)
ex_hl

ex_lakes <- data.frame(id  = lake_meta_dat$id[ex_ids],
                       lat = lake_meta_dat$lat[ex_ids],
                       lon = lake_meta_dat$lon[ex_ids])

targets <- data.frame(state = c("oligotrophic", "eutrophic"),
                      tp_target = c("~0.010", ">0.100"),
                      tn_target = c("<=0.35", ">1.2"))

# ---- Set up and run each trophic state ---------------------------------------
cmp <- lapply(names(trophic_presets), function(state) {
  preset <- trophic_presets[[state]]
  state_dir <- file.path(ex_dir, state)

  dirs <- setup_ler_lakes(lake_id       = ex_ids,
                          lake_meta     = lake_meta_dat,
                          config_file   = file.path(template_dir, "LakeEnsemblR.yaml"),
                          out_path      = file.path(state_dir, "runs"),
                          nc_files_met  = met_paths,
                          nc_file_hypso = hypso_nc,
                          models        = ler_models,
                          spin_up_years = spin_up)
  copy_wq_templates(dirs, template_dir)
  for (i in seq_along(dirs)) {
    d <- dirs[i]
    add_generic_inflow(d, residence_time_d = ex_hl$Res_time[i], conc = preset$inflow)
    set_initial_nutrients(d, preset$init)
  }
  print(for_each_lake(dirs, setup_wq_lake))
  run_log <- for_each_lake(dirs, run_wq_lake, models = wq_models)
  print(run_log)

  lakes <- cbind(ex_lakes, folder = dirs)[run_log$ok, ]
  create_isimip_global(lakes,
                       model      = isimip_models,
                       start_year = 1991 - spin_up,
                       end_year   = 2000,
                       out_dir    = file.path(state_dir, "isimip_global"),
                       isimip     = modifyList(isimip_info,
                                               list(forcing = "gswp3-era5",
                                                    climate_scenario = "obsclim",
                                                    time_ref = "1901-01-01")))
  cbind(state = state,
        bind_rows(read_isimip_lakes(file.path(state_dir, "isimip_global"), lakes),
                  read_temp_epi_hypo(lakes, isimip_models)))
}) |> bind_rows()

# mol m-3 -> mg/L for TN, TP and DO, g m-3 -> ug/L for chl
cmp <- cmp |>
  mutate(value = case_when(var == "tn"  ~ value * 14.007,
                           var == "tp"  ~ value * 30.974,
                           var == "do"  ~ value * 31.998,
                           var == "chl" ~ value * 1000,
                           TRUE ~ value),
         units = case_when(var %in% c("tn", "tp", "do") ~ "mg L-1",
                           var == "chl" ~ "ug L-1",
                           TRUE ~ units))

# ---- Compare with the targets (after spin-up, epilimnion) ---------------------
cmp |>
  filter(year(date) >= 1991, level == "epi", var %in% c("tp", "tn", "chl"), !is.na(value)) |>
  group_by(lake, state, model, var) |>
  summarise(mean = signif(mean(value), 3), .groups = "drop") |>
  pivot_wider(names_from = var, values_from = mean) |>
  left_join(targets, by = "state") |>
  arrange(lake, desc(state), model) |>
  print(n = Inf)

# Time series, one multipanel plot per lake and trophic state: variables in
# rows, epilimnion (left) and hypolimnion (right) in columns; epi and hypo
# share the y axis of their row (dashed line = end of spin-up)
plot_vars <- c(tn = "TN", tp = "TP", chl = "Chl-a", do = "DO", temp = "Temperature")
ts <- cmp |>
  filter(var %in% names(plot_vars), !is.na(value)) |>
  mutate(var_lab = factor(paste0(plot_vars[var], " (", units, ")")),
         var_lab = reorder(var_lab, match(var, names(plot_vars))),
         level   = factor(level, levels = c("epi", "hypo"),
                          labels = c("Epilimnion", "Hypolimnion")))
plots <- list()
for (lk in unique(ts$lake)) for (st in c("oligotrophic", "eutrophic")) {
  plots[[paste(lk, st, sep = "_")]] <-
    ggplot2::ggplot(ts[ts$lake == lk & ts$state == st, ],
                    ggplot2::aes(x = date, y = value, colour = model)) +
    ggplot2::geom_line(linewidth = 0.3) +
    ggplot2::geom_vline(xintercept = as.Date("1991-01-01"), linetype = "dashed") +
    ggplot2::facet_grid(var_lab ~ level, scales = "free_y", drop = FALSE) +
    ggplot2::labs(x = NULL, y = NULL, colour = "Model", title = paste(lk, st, sep = " - ")) +
    ggplot2::theme_bw() +
    ggplot2::theme(legend.position = "bottom")
}
for (p in plots) print(p)
# save them all:
# for (n in names(plots)) ggplot2::ggsave(file.path(ex_dir, paste0(n, ".png")), plots[[n]], width = 10, height = 12)
