# Step 3 (after all array tasks): write the ISIMIP lakes_global files
#
#   Rscript scripts/03_isimip_output.R <set> <model>
#
# e.g. lownutr GLM. One file per variable and decade, all lakes of the set
# that ran with this model; the set name is the sens_scenario in the file
# name. Sets and models write different files, so these jobs can run in
# parallel (but only after step 2 has finished).

source("scripts/00_settings.R")

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2) stop("Usage: Rscript scripts/03_isimip_output.R <set> <model>")
set <- args[1]
model <- args[2]
stopifnot(set %in% c(names(nutr_scenarios), "default"), model %in% isimip_models)

logs <- do.call(rbind, lapply(list.files(log_dir, "^task_.*\\.csv$", full.names = TRUE),
                              read.csv))
logs <- logs[logs$set == set & logs$ok &
               vapply(strsplit(logs$models_ok, ","), function(m) model %in% m, logical(1)), ]
logs <- logs[file.exists(file.path(logs$folder, "metrics.rds")), ]
message(set, " / ", model, ": ", nrow(logs), " lakes")

lakes <- data.frame(id  = lake_meta_dat$id[logs$row],
                    lat = lake_meta_dat$lat[logs$row],
                    lon = lake_meta_dat$lon[logs$row],
                    rds = file.path(logs$folder, "metrics.rds"))

# Output years: the forcing period, without the spin-up
met_paths <- create_cdata_paths(forcing_dir, climate, forcing)
years <- range(as.numeric(unlist(strsplit(unique(met_paths$per), "_"))))

comment <- if (set == "default") {
  paste("Lakes without discharge in HydroLAKES (Res_time -1 or missing): no inflow,",
        "outflow or external nutrient loading")
} else {
  conc <- nutr_scenarios[[set]]
  paste0("Generic inflow with constant concentrations (g m-3): ",
         paste(names(conc), conc, sep = " ", collapse = ", "),
         "; flow from HydroLAKES residence time (clamped to 7 d - 100 yr)")
}

create_isimip_global(lakes,
                     model        = model,
                     start_year   = years[1],
                     end_year     = years[2],
                     phyto_groups = character(),   # no phytobio-<group> files
                     out_dir      = out_dir,
                     isimip       = modifyList(isimip_info, list(sens_scenario = set,
                                                                 comment = comment,
                                                                 variables = isimip_variables)))
