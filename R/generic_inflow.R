# Generic in- and outflow with constant nutrient concentrations, for testing
# the WQ models before real inflow data are available.

#' Add a generic inflow (with N, P and Si) and an equal outflow to a lake
#'
#' Flow is set from the lake volume and a residence time, inflow temperature
#' follows the 7-day mean air temperature (>= 0 degC), and the nutrient
#' concentrations are constant. Writes the LakeEnsemblR in-/outflow files and
#' WQ_input_files/nutrient_inputs.csv, switches in-/outflows on in
#' LakeEnsemblR.yaml and LakeEnsemblR_WQ.yaml, and re-exports the physical
#' model configs. Run after copy_wq_templates() and before setup_wq_lake().
#'
#' @param folder Lake folder (from setup_ler_lakes())
#' @param residence_time_d Hydraulic residence time (days); ignored when
#'   `discharge` is given
#' @param discharge Mean discharge (m3 s-1), e.g. HydroLAKES Dis_avg from
#'   get_lake_discharge(); NULL = use `residence_time_d`
#' @param conc Inflow concentrations in g m-3 as element (P, N, Si):
#'   PO4-P, POP, NH4-N, NO3-N, Silica (Si)
#' @param models Physical models to re-export
add_generic_inflow <- function(folder, residence_time_d = 365, discharge = NULL,
                               conc = c(PO4 = 0.02, POP = 0.02, NH4 = 0.05,
                                        NO3 = 1.0, Silica = 2.0),
                               models = c("GLM", "GOTM", "Simstrat")) {
  met <- read.csv(file.path(folder, "meteo.csv"))
  hyps <- read.csv(file.path(folder, "hypsograph.csv"))
  hyps <- hyps[order(hyps$Depth_meter), ]

  volume <- sum(diff(hyps$Depth_meter) *
                  (head(hyps$Area_meterSquared, -1) + tail(hyps$Area_meterSquared, -1)) / 2)
  if (is.null(discharge)) {
    flow <- volume / (residence_time_d * 86400)
  } else {
    flow <- discharge
    residence_time_d <- volume / flow / 86400
  }

  datetime <- paste(as.Date(met$datetime), "00:00:00")
  wtemp <- pmax(0, zoo::rollmean(met$Air_Temperature_celsius, 7, fill = "extend"))

  write.csv(data.frame(datetime = datetime,
                       Flow_metersCubedPerSecond = flow,
                       Water_Temperature_celsius = round(wtemp, 2),
                       Salinity_practicalSalinityUnits = 0),
            file.path(folder, "LakeEnsemblR_inflow_standard.csv"),
            quote = FALSE, row.names = FALSE)
  write.csv(data.frame(datetime = datetime, Flow_metersCubedPerSecond = flow),
            file.path(folder, "LakeEnsemblR_outflow_standard.csv"),
            quote = FALSE, row.names = FALSE)

  nutr <- data.frame(datetime = datetime)
  for (v in names(conc)) nutr[[paste0("wq_", v, "_gramsPerCubicMeter_1")]] <- conc[[v]]
  dir.create(file.path(folder, "WQ_input_files"), showWarnings = FALSE)
  write.csv(nutr, file.path(folder, "WQ_input_files", "nutrient_inputs.csv"),
            quote = FALSE, row.names = FALSE)

  ler_yaml <- file.path(folder, "LakeEnsemblR.yaml")
  input_yaml_multiple(ler_yaml, value = "true", key1 = "inflows", key2 = "use", verbose = FALSE)
  input_yaml_multiple(ler_yaml, value = "true", key1 = "outflows", key2 = "use", verbose = FALSE)
  # Surface outflow: outflow_lvl is the height above the bottom (the template
  # value comes from another lake). 5 cm below the surface, as GLM rejects an
  # outlet even slightly above its crest.
  y <- readLines(ler_yaml)
  i_lvl <- grep("^\\s*outflow_lvl:", y)
  i_item <- i_lvl + which(grepl("^\\s*-\\s*[0-9.]+", y[-(1:i_lvl)]))[1]
  y[i_item] <- sub("-\\s*[0-9.]+", paste("-", max(hyps$Depth_meter) - 0.05), y[i_item])
  writeLines(y, ler_yaml)
  input_yaml_multiple(file.path(folder, "LakeEnsemblR_WQ.yaml"),
                      value = "WQ_input_files/nutrient_inputs.csv",
                      key1 = "input", key2 = "inflows", verbose = FALSE)

  wd <- getwd()
  on.exit(setwd(wd))
  setwd(folder)
  suppressMessages(export_config(config_file = "LakeEnsemblR.yaml", model = models))
  # export_config() rewrites glm3.nml; keep evaporation and rain off as in setup_ler_lakes()
  if ("GLM" %in% models) {
    nml <- read_nml(file.path("GLM", "glm3.nml"))
    nml[["debugging"]][["disable_evap"]] <- TRUE
    nml[["meteorology"]][["rain_factor"]] <- 0
    write_nml(nml, file.path("GLM", "glm3.nml"))
  }

  message(basename(folder), ": volume ", signif(volume, 3), " m3, flow ",
          signif(flow, 3), " m3/s (residence time ", signif(residence_time_d, 3), " d)")
  invisible(flow)
}

#' HydroLAKES attributes of the lakes
#'
#' @param lake_id Rows of `lake_meta`
#' @param file CSV exported from the HydroLAKES attribute table (Hylak_id,
#'   Lake_type, Lake_area, Vol_total, Depth_avg, Dis_avg, Res_time, Wshd_area)
#' @returns One row per lake, in the order of `lake_id`; -9999 set to NA
get_hydrolakes <- function(lake_id, lake_meta, file = "data/hydrolakes_attributes_all.csv") {
  hl <- read.csv(file)
  hl <- hl[match(lake_meta$hydrolakes[lake_id], hl$Hylak_id), ]
  hl[hl == -9999] <- NA
  rownames(hl) <- NULL
  hl
}

#' Residence time and scenario set of every lake for the global runs
#'
#' Lakes without discharge in HydroLAKES (Res_time -1, Dis_avg 0: closed
#' lakes) or without data (-9999) get no inflow and go to the `default` set.
#' All others get a generic inflow in the nutrient scenarios, with the
#' HydroLAKES residence time clamped to [tau_min, tau_max] days.
#'
#' @param lake_meta Lake metadata (`lake_meta_dat`)
#' @param file HydroLAKES attribute table (see get_hydrolakes())
#' @returns One row per lake (row = row of `lake_meta`) with `res_time_hl`
#'   (HydroLAKES, days; NA = no data), `res_time` (used, days; NA = no
#'   inflow), `flag` (ok, short, long, no_discharge, no_data) and `set`
#'   ("inflow" or "default")
make_inflow_table <- function(lake_meta, file = "data/hydrolakes_attributes_all.csv",
                              tau_min = 7, tau_max = 36500) {
  hl <- get_hydrolakes(seq_len(nrow(lake_meta)), lake_meta, file)
  rt <- hl$Res_time
  flag <- case_when(is.na(rt)     ~ "no_data",
                    rt <= 0       ~ "no_discharge",
                    rt < tau_min  ~ "short",
                    rt > tau_max  ~ "long",
                    TRUE          ~ "ok")
  data.frame(row         = seq_len(nrow(lake_meta)),
             id          = lake_meta$id,
             hydrolakes  = lake_meta$hydrolakes,
             res_time_hl = rt,
             res_time    = ifelse(flag %in% c("no_data", "no_discharge"), NA,
                                  pmin(pmax(rt, tau_min), tau_max)),
             flag        = flag,
             set         = ifelse(flag %in% c("no_data", "no_discharge"), "default", "inflow"))
}
