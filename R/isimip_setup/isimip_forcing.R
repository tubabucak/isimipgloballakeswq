# Copied from ISIMIPglobalLER (github: isimipgloballer, commit a8d9608),
# author Johannes Feldbauer, GPL (>= 3).
# Changes: extract_var_id() and load_hypso() always use the multi-lake format
# (so a single lake works too) and read the lakes' bounding box in blocks
# instead of the whole global field; joins use explicit keys.

#' Read a (lon, lat, z) variable at the given grid cells
#'
#' Reads the bounding box of the cells in blocks along z (at most
#' `max_values` values per block) and picks out the cells. ISIMIP files are
#' chunked per global time step, so this decompresses each chunk only once,
#' whereas reading cell by cell decompresses the whole file for every cell.
#' @returns Matrix with one row per cell
read_cells <- function(nc, var, x_id, y_id, max_values = 5e7) {
  nx <- diff(range(x_id)) + 1
  ny <- diff(range(y_id)) + 1
  nz <- nc$var[[var]]$varsize[3]
  nc_cells <- length(x_id)
  block <- max(1, min(nz, floor(max_values / (nx * ny))))
  idx <- cbind(x_id - min(x_id) + 1, y_id - min(y_id) + 1)

  out <- matrix(NA_real_, nc_cells, nz)
  for (z0 in seq(1, nz, by = block)) {
    n <- min(block, nz - z0 + 1)
    b <- ncvar_get(nc, var, start = c(min(x_id), min(y_id), z0),
                   count = c(nx, ny, n), collapse_degen = FALSE)
    out[, z0:(z0 + n - 1)] <- b[cbind(idx[rep(seq_len(nc_cells), n), , drop = FALSE],
                                      rep(seq_len(n), each = nc_cells))]
  }
  out
}

#' List the ISIMIP meteo forcing files for a scenario and GCM
#'
#' @param base_dir Directory with subfolders <scen>/<gcm> holding the ISIMIP
#'   files, or (with `scen` and `gcm` NULL) the folder with the files itself
#' @returns data.frame with columns file, var, per, path
#' @details Works for global files (`..._tas_global_daily_...`) and regional
#'   extracts (`..._tas_dnk_30arcmin_daily_...`).
create_cdata_paths <- function(base_dir, scen = NULL, gcm = NULL) {
  cdata_scen <- do.call(file.path, as.list(c(base_dir, scen, gcm)))
  # files directly in base_dir (e.g. example_climate/) are used as well
  if (!dir.exists(cdata_scen)) {
    message("No folder ", cdata_scen, "; using the files in ", base_dir)
    cdata_scen <- base_dir
  }
  files <- data.frame(file = list.files(cdata_scen, pattern = "_daily_.*[.]nc$"))
  files |>
    mutate(var = case_when(grepl("_hurs_", file) ~ "rel_h",
                           grepl("_tas_", file) ~ "at",
                           grepl("_sfcwind_", file) ~ "wind",
                           grepl("_rlds_", file) ~ "lwr",
                           grepl("_rsds_", file) ~ "swr",
                           grepl("_prsn_", file) ~ "snow",
                           grepl("_ps_", file) ~ "p",
                           grepl("_pr_", file) ~ "prec"),
           per = gsub("\\.nc", "", gsub(".*_daily_", "", file))) |>
    filter(!is.na(var)) |>
    mutate(path = gsub("/+", "/", file.path(cdata_scen, file)))
}

#' Extract a variable at the lakes' grid cells from an ISIMIP netcdf file
#'
#' @param x_id,y_id Grid indices (longitude, latitude) of the lakes
#' @returns Matrix with one row per lake and one column per time step
extract_var_id <- function(ncfile, x_id, y_id, var = NULL) {

  nc <- nc_open(ncfile, readunlim = FALSE, suppress_dimvals = TRUE)
  on.exit(nc_close(nc))

  if(is.null(var)) var <- names(nc$var)[1]

  read_cells(nc, var, x_id, y_id)
}

#' Meteo forcing for LakeEnsemblR from ISIMIP netcdf files for several lakes
#'
#' @param lake_id Ids of the lakes (rows of `lake_meta`)
#' @param ncfiles One-row data.frame/list with paths, names `rel_h`, `at`,
#'   `wind`, `lwr`, `swr`, `snow`, `p`, `prec`
#' @returns data.frame with `datetime`, `lake_id` ("lake_<id>") and the
#'   LakeEnsemblR meteo columns
load_met_forc_multi <- function(lake_id, ncfiles, lake_meta) {

  x_id <- lake_meta$x_id[lake_id]
  y_id <- lake_meta$y_id[lake_id]

  # time
  nc <- nc_open(ncfiles$at)
  time <- ncvar_get(nc, "time")
  time_meta <- ncatt_get(nc, "time")
  time <- as.POSIXct(gsub("days since ", "", time_meta$units), tz = "UTC") + time*86400
  nc_close(nc)

  # one long data.frame (datetime, lake_id, value) per variable
  read_long <- function(file, name) {
    v <- extract_var_id(file, x_id, y_id)
    data.frame(t(v), time) |> setNames(c(lake_id, "datetime")) |>
      pivot_longer(cols = seq_along(lake_id), names_to = "lake_id",
                   values_to = name)
  }

  at <- read_long(ncfiles$at, "Air_Temperature_celsius") |>
    mutate(Air_Temperature_celsius = Air_Temperature_celsius - 273.15)
  rel_h <- read_long(ncfiles$rel_h, "Relative_Humidity_percent")
  wind <- read_long(ncfiles$wind, "Ten_Meter_Uwind_vector_meterPerSecond") |>
    mutate(Ten_Meter_Vwind_vector_meterPerSecond = 0)
  lwr <- read_long(ncfiles$lwr, "Longwave_Radiation_Downwelling_wattPerMeterSquared")
  swr <- read_long(ncfiles$swr, "Shortwave_Radiation_Downwelling_wattPerMeterSquared")
  snow <- read_long(ncfiles$snow, "Snowfall_millimeterPerDay") |>
    mutate(Snowfall_millimeterPerDay = Snowfall_millimeterPerDay*24*3600)
  prec <- read_long(ncfiles$prec, "Precipitation_millimeterPerDay") |>
    mutate(Precipitation_millimeterPerDay = Precipitation_millimeterPerDay*24*3600)
  p <- read_long(ncfiles$p, "Surface_Level_Barometric_Pressure_pascal")
  gc()

  keys <- c("datetime", "lake_id")
  met_out <- left_join(at, rel_h, by = keys) |> left_join(wind, by = keys) |>
    left_join(lwr, by = keys) |> left_join(swr, by = keys) |>
    left_join(p, by = keys) |> left_join(snow, by = keys) |>
    left_join(prec, by = keys) |>
    mutate(Rainfall_millimeterPerDay = Precipitation_millimeterPerDay -
             Snowfall_millimeterPerDay) |>
    mutate(lake_id = paste0("lake_", lake_id)) |>
    left_join(select(lake_meta, id, lat, lon, elevation), by = c(lake_id = "id"))

  # calculate cloud cover and dew point (per day, as in ISIMIPglobalLER)
  met_out <- met_out |> group_by(datetime, lake_id) |>
    mutate(Cloud_Cover_decimalFraction = calc_cc_dewp(date = datetime,
                                                      airt = Air_Temperature_celsius,
                                                      relh = Relative_Humidity_percent,
                                                      swr = Shortwave_Radiation_Downwelling_wattPerMeterSquared,
                                                      lat = lat,
                                                      lon = lon,
                                                      elev = elevation)$ccsim,
           Dewpoint_Temperature_celsius = calc_cc_dewp(date = datetime,
                                                       airt = Air_Temperature_celsius,
                                                       relh = Relative_Humidity_percent,
                                                       swr = Shortwave_Radiation_Downwelling_wattPerMeterSquared,
                                                       lat = lat,
                                                       lon = lon,
                                                       elev = elevation)$dewt_daily) |>
    select(-lat, -lon, -elevation) |>
    ungroup()

  met_out
}

#' Hypsographs from the ISIMIP hypsograph netcdf file
#'
#' @param lake_id Ids of the lakes (used to label the rows)
#' @returns data.frame with `lake_id`, `d_id`, `Depth_meter`, `Area_meterSquared`
load_hypso <- function(x_id, y_id, ncfile, lake_id) {

  nc <- nc_open(ncfile)
  on.exit(nc_close(nc))

  a <- read_cells(nc, "area", x_id, y_id)
  a <- data.frame(t(a), seq_len(ncol(a))) |> setNames(c(lake_id, "d_id")) |>
    pivot_longer(cols = seq_along(lake_id), names_to = "lake_id",
                 values_to = "Area_meterSquared") |>
    group_by(lake_id) |>
    mutate(Area_meterSquared = rev(Area_meterSquared*10^6)) |>
    ungroup()

  h <- read_cells(nc, "levels", x_id, y_id)
  h <- data.frame(t(h), seq_len(ncol(h))) |> setNames(c(lake_id, "d_id")) |>
    pivot_longer(cols = seq_along(lake_id), names_to = "lake_id",
                 values_to = "Depth_meter") |>
    group_by(lake_id) |>
    mutate(Depth_meter = rev(max(Depth_meter) - Depth_meter)) |>
    ungroup()

  left_join(h, a, by = c("lake_id", "d_id"))
}
