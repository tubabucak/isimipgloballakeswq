# Generic in- and outflow with constant nutrient concentrations, for testing
# the WQ models before real inflow data are available.

#' Add a generic inflow (with N, P and Si) and an equal outflow to a lake
#'
#' Flow is set from the lake volume and a residence time, inflow temperature
#' follows the 7-day mean air temperature (>= 0 degC), oxygen is at
#' saturation for that temperature, and the nutrient concentrations are
#' constant. Writes the LakeEnsemblR in-/outflow files and
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
  # Oxygen at saturation for the inflow temperature (APHA polynomial, mg/L);
  # without it the AED models get oxygen-free inflow
  nutr$wq_DO_gramsPerCubicMeter_1 <- round(14.652 - 0.41022 * wtemp + 0.007991 * wtemp^2 -
                                             0.000077774 * wtemp^3, 2)
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
#' Lakes with HydroLAKES discharge use the HydroLAKES residence time. For
#' lakes without discharge (Res_time -1, Dis_avg 0: mostly terminal lakes in
#' arid basins) or without data (-9999: small islands, far Arctic) the
#' discharge is estimated from the watershed area (`estimate_missing`):
#'
#' * fit log10(Dis_avg) ~ log10(Wshd_area) on the lakes with discharge
#'   (R2 ~0.78);
#' * lakes without a watershed area (-9999) get Wshd_area = their lake area x
#'   the median Wshd_area / Lake_area of the lakes with discharge in the same
#'   |latitude| band (`lat_bands`; ~7 north of 66.5, 16-51 elsewhere),
#'   capped at the global median (~24) as these are mostly small island lakes;
#' * regional correction: the fit is multiplied by the median ratio of
#'   HydroLAKES to fitted discharge of the lakes with discharge within
#'   `radius_deg` (at least `min_neighbours`, otherwise no correction), so
#'   arid regions get less water than the global fit gives;
#' * residence time = Vol_total / discharge.
#'
#' All residence times are clamped to [tau_min, tau_max] days. Without
#' `estimate_missing`, lakes without discharge or data get no inflow and go
#' to the `default` set.
#'
#' @param lake_meta Lake metadata (`lake_meta_dat`)
#' @param file HydroLAKES attribute table (see get_hydrolakes())
#' @param estimate_missing Estimate the discharge of lakes without it (TRUE),
#'   or leave them without inflow in the `default` set (FALSE)
#' @param radius_deg,min_neighbours Neighbourhood of the regional correction
#' @param lat_bands |latitude| band limits for the watershed / lake area ratio
#' @returns One row per lake (row = row of `lake_meta`) with `res_time_hl`
#'   (HydroLAKES, days; NA = no data), `res_time_est` (estimated, days; NA =
#'   not estimated), `res_time` (used, days; NA = no inflow), `flag`
#'   (HydroLAKES status: ok, short, long, no_discharge, no_data), `source`
#'   (hydrolakes, est_wshd, est_wshd_assumed, none) and `set` ("inflow" or
#'   "default")
make_inflow_table <- function(lake_meta, file = "data/hydrolakes_attributes_all.csv",
                              tau_min = 7, tau_max = 36500, estimate_missing = TRUE,
                              radius_deg = 5, min_neighbours = 10,
                              lat_bands = c(0, 30, 50, 66.5, 90)) {
  hl <- get_hydrolakes(seq_len(nrow(lake_meta)), lake_meta, file)
  rt <- hl$Res_time
  flag <- case_when(is.na(rt)     ~ "no_data",
                    rt <= 0       ~ "no_discharge",
                    rt < tau_min  ~ "short",
                    rt > tau_max  ~ "long",
                    TRUE          ~ "ok")
  missing <- flag %in% c("no_data", "no_discharge")
  source <- ifelse(missing, "none", "hydrolakes")
  rt_est <- rep(NA_real_, length(rt))

  if (estimate_missing && any(missing)) {
    has_q <- !missing & hl$Dis_avg > 0 & hl$Wshd_area > 0
    fit <- lm(log10(Dis_avg) ~ log10(Wshd_area), data = hl[has_q, ])
    resid <- residuals(fit)

    # no watershed area: lake area x median Wshd_area / Lake_area of the lakes
    # with discharge in the same latitude band (~7 in the Arctic, 16-51
    # elsewhere), at most the global median (~24): these are mostly small
    # island lakes, where the island limits the catchment
    wshd <- hl$Wshd_area
    no_wshd <- missing & (is.na(wshd) | wshd <= 0)
    wshd_ratio <- hl$Wshd_area[has_q] / hl$Lake_area[has_q]
    band <- cut(abs(lake_meta$lat), lat_bands, include.lowest = TRUE)
    ratio <- pmin(tapply(wshd_ratio, band[has_q], median), median(wshd_ratio))
    wshd[no_wshd] <- ratio[as.character(band[no_wshd])] * hl$Lake_area[no_wshd]

    # median residual (log10) of the lakes with discharge nearby
    lat_q <- lake_meta$lat[has_q]
    lon_q <- lake_meta$lon[has_q]
    corr <- vapply(which(missing), function(i) {
      dx <- (lon_q - lake_meta$lon[i]) * cos(lake_meta$lat[i] * pi / 180)
      near <- sqrt((lat_q - lake_meta$lat[i])^2 + dx^2) <= radius_deg
      if (sum(near) >= min_neighbours) median(resid[near]) else 0
    }, numeric(1))

    q_est <- 10^(predict(fit, data.frame(Wshd_area = wshd[missing])) + corr)   # m3 s-1
    rt_est[missing] <- hl$Vol_total[missing] * 1e6 / q_est / 86400            # Vol_total in mcm
    source[missing] <- ifelse(no_wshd[missing], "est_wshd_assumed", "est_wshd")
    message("Discharge estimated for ", sum(missing), " lakes: log10(Q) = ",
            paste(signif(coef(fit), 3), collapse = " + "), " x log10(Wshd_area), R2 ",
            round(summary(fit)$r.squared, 2), "; regional correction x",
            paste(signif(10^range(corr), 2), collapse = " - "))
  }

  rt_used <- ifelse(source == "none", NA, ifelse(missing, rt_est, rt))
  data.frame(row          = seq_len(nrow(lake_meta)),
             id           = lake_meta$id,
             hydrolakes   = lake_meta$hydrolakes,
             res_time_hl  = rt,
             res_time_est = rt_est,
             res_time     = pmin(pmax(rt_used, tau_min), tau_max),
             flag         = flag,
             source       = source,
             set          = ifelse(source == "none", "default", "inflow"))
}
