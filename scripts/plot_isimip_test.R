# Plots of the ISIMIP files of a test run (e.g. the 40 Danish lakes)
#
#   Rscript scripts/plot_isimip_test.R [isimip_dir] [out_dir]
#
# isimip_dir: folder with the *_global_daily_*.nc files
#   (default isimip_global/obsclim/gswp3-era5)
# out_dir: where the plots go (default <isimip_dir>/plots)
#
# The lakes are the grid cells with data, matched to lake_meta_dat. Plots
# (PNG, and all in plots.pdf):
#   1 scenario_contrast  10-year epilimnion mean per lake, model and scenario
#   2 seasonal_cycle     monthly mean over the lakes, epilimnion and hypolimnion
#   3 tp_vs_chl          lake means of TP against Chl-a (nutrient response)
#   4 tp_vs_restime      lake mean TP against the residence time used
#   5 map_<var>          10-year epilimnion mean per lake on a map
#   6 lake_<id>          daily time series of one lake (the deepest)

suppressPackageStartupMessages({
  library(dplyr)
  library(ncdf4)
  library(ggplot2)
})
source("R/compare_models.R")
load("data/lake_meta_dat.rda")

args <- commandArgs(trailingOnly = TRUE)
isimip_dir <- if (length(args) >= 1) args[1] else "isimip_global/obsclim/gswp3-era5"
out_dir    <- if (length(args) >= 2) args[2] else file.path(isimip_dir, "plots")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# ---- Lakes: cells with data in the first file -----------------------------
f1 <- list.files(isimip_dir, "_global_daily_.*[.]nc$", full.names = TRUE)[1]
if (is.na(f1)) stop("No ISIMIP files in ", isimip_dir)
nc <- nc_open(f1)
first <- ncvar_get(nc, names(nc$var)[1], start = c(1, 1, 1, 1), count = c(-1, -1, 1, 1))
cells <- which(!is.na(first) & first < 1e19, arr.ind = TRUE)
cells <- data.frame(lon = ncvar_get(nc, "lon")[cells[, 1]], lat = ncvar_get(nc, "lat")[cells[, 2]])
nc_close(nc)
lakes <- lake_meta_dat |>
  mutate(row = row_number()) |>
  inner_join(cells, by = c("lat", "lon"))
message(nrow(lakes), " lakes")

# ---- Read and convert to familiar units -----------------------------------
var_labels <- c(watertemp = "Temperature (°C)", do = "DO (mg O2/L)", tp = "TP (µg P/L)",
           tn = "TN (mg N/L)", chl = "Chl-a (µg/L)", zoobio = "Zoopl. (mg C/L)")
to_units <- function(var, x) {
  switch(var,
         watertemp = x - 273.15,  # K
         do        = x * 32,      # mol O2 m-3
         tp        = x * 30974,   # mol P m-3
         tn        = x * 14.007,  # mol N m-3
         chl       = x * 1000,    # g m-3
         zoobio    = x * 12.011,  # mol C m-3
         x)
}
df <- read_isimip_lakes(isimip_dir, lakes) |>
  filter(!is.na(value), value < 1e19) |>
  group_by(var) |>
  mutate(value = to_units(var[1], value)) |>
  ungroup() |>
  mutate(panel    = factor(var_labels[var], levels = var_labels),
         scenario = factor(scenario, levels = intersect(c("lownutr", "highnutr", "default"),
                                                        unique(scenario))))
message("Models: ", paste(unique(df$model), collapse = ", "),
        "; scenarios: ", paste(levels(df$scenario), collapse = ", "))

lake_means <- df |>
  group_by(model, scenario, var, panel, lake, level) |>
  summarise(value = mean(value), .groups = "drop")

plots <- list()

# 1 Scenario contrast per model
plots$scenario_contrast <- lake_means |>
  filter(level == "epi") |>
  ggplot(aes(model, value, fill = scenario)) +
  geom_boxplot(outlier.size = 0.6) +
  facet_wrap(~panel, scales = "free_y") +
  labs(x = NULL, y = NULL, fill = "Scenario",
       title = "10-year epilimnion mean per lake",
       subtitle = paste(nrow(lakes), "lakes")) +
  theme_bw() +
  theme(axis.text.x = element_text(angle = 30, hjust = 1))

# 2 Seasonal cycle, mean over the lakes
plots$seasonal_cycle <- df |>
  mutate(month = as.integer(format(date, "%m"))) |>
  group_by(model, scenario, panel, level, month) |>
  summarise(value = mean(value), .groups = "drop") |>
  ggplot(aes(month, value, colour = model, linetype = scenario)) +
  geom_line() +
  facet_grid(panel ~ level, scales = "free_y") +
  scale_x_continuous(breaks = c(1, 4, 7, 10), labels = month.abb[c(1, 4, 7, 10)]) +
  labs(x = NULL, y = NULL, colour = "Model", linetype = "Scenario",
       title = "Monthly mean over all lakes") +
  theme_bw()

# 3 Nutrient response: TP against Chl-a
wide <- lake_means |>
  filter(level == "epi") |>
  select(model, scenario, lake, var, value) |>
  tidyr::pivot_wider(names_from = var, values_from = value)
if (all(c("tp", "chl") %in% names(wide))) {
  plots$tp_vs_chl <- ggplot(wide, aes(tp, chl, colour = scenario)) +
    geom_point() +
    facet_wrap(~model) +
    scale_x_log10() + scale_y_log10() +
    labs(x = var_labels[["tp"]], y = var_labels[["chl"]], colour = "Scenario",
         title = "Epilimnion TP against Chl-a (10-year lake means)") +
    theme_bw()
}

# 4 In-lake TP against the residence time used for the inflow
if (file.exists("data/inflow_table.csv") && "tp" %in% names(wide)) {
  it <- read.csv("data/inflow_table.csv")
  rt <- wide |>
    left_join(data.frame(lake = lake_meta_dat$id[it$row], res_time = it$res_time), by = "lake") |>
    filter(!is.na(res_time))
  if (nrow(rt) > 0) {
    plots$tp_vs_restime <- ggplot(rt, aes(res_time, tp, colour = model)) +
      geom_point() +
      facet_wrap(~scenario) +
      scale_x_log10() + scale_y_log10() +
      labs(x = "Residence time (days)", y = var_labels[["tp"]], colour = "Model",
           title = "Epilimnion TP against residence time (10-year lake means)") +
      theme_bw()
  }
}

# 5 Maps, one per variable
world <- if (requireNamespace("maps", quietly = TRUE)) map_data("world") else NULL
map_df <- lake_means |>
  filter(level == "epi") |>
  left_join(lakes |> select(lake = id, lat, lon), by = "lake")
for (v in intersect(names(var_labels), unique(map_df$var))) {
  d <- map_df[map_df$var == v, ]
  p <- ggplot(d, aes(lon, lat))
  if (!is.null(world)) {
    p <- p + geom_polygon(data = world, aes(long, lat, group = group),
                          fill = "grey92", colour = "grey60", linewidth = 0.2)
  }
  plots[[paste0("map_", v)]] <- p +
    geom_tile(aes(fill = value), width = 0.5, height = 0.5) +
    facet_grid(scenario ~ model) +
    coord_quickmap(xlim = range(d$lon) + c(-1, 1), ylim = range(d$lat) + c(-1, 1)) +
    scale_fill_viridis_c() +
    labs(x = NULL, y = NULL, fill = NULL, title = paste(var_labels[[v]], "- 10-year epilimnion mean")) +
    theme_bw()
}

# 6 Time series of the deepest lake
deep <- lakes$id[which.max(lakes$depth)]
plots[[deep]] <- df |>
  filter(lake == deep) |>
  ggplot(aes(date, value, colour = model, linetype = scenario)) +
  geom_line(linewidth = 0.3) +
  facet_grid(panel ~ level, scales = "free_y") +
  labs(x = NULL, y = NULL, colour = "Model", linetype = "Scenario",
       title = paste0(deep, " (", round(max(lakes$depth), 1), " m)")) +
  theme_bw()

# ---- Save -----------------------------------------------------------------
for (n in names(plots)) {
  ggsave(file.path(out_dir, paste0(n, ".png")), plots[[n]], width = 11, height = 7.5, dpi = 120)
}
pdf(file.path(out_dir, "plots.pdf"), width = 11, height = 7.5)
invisible(lapply(plots, print))
dev.off()
message("Plots in ", out_dir)

# Time series test for a single lake
lake <- lake_meta_dat[lake_meta_dat$id == "lake_26164", c("id", "lat", "lon")]
df <- read_isimip_lakes("isimip_global/obsclim/gswp3-era5", lakes = lake)
plot_model_comparison(df, lake = "lake_26164")
