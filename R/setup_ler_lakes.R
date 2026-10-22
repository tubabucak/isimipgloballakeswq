# Create the LakeEnsemblR (physical) set-up for a set of ISIMIP global lakes.
# Based on set_up_lake_multiple() from ISIMIPglobalLER.

#' Set up LakeEnsemblR folders for several lakes
#'
#' For each lake: writes LakeEnsemblR.yaml with lake-specific values,
#' meteo.csv, hypsograph.csv and init_temp_prof.csv, optionally adds a
#' spin-up period, and runs LakeEnsemblR::export_config().
#'
#' @param lake_id Ids of the lakes (rows of `lake_meta`)
#' @param lake_meta Lake metadata (`lake_meta_dat`)
#' @param config_file Path to the template LakeEnsemblR.yaml
#' @param out_path Base folder; lakes go to <out_path>/lake_<id>
#' @param nc_files_met Output of `create_cdata_paths()`
#' @param nc_file_hypso Path to the ISIMIP hypsograph netcdf file
#' @param models Physical models to export
#' @param spin_up_years Spin-up years to add (0 = none)
#' @param sdigs Significant digits for the forcing files
#' @returns The lake folders, invisibly
setup_ler_lakes <- function(lake_id, lake_meta, config_file, out_path,
                            nc_files_met, nc_file_hypso,
                            models = c("GLM", "GOTM", "Simstrat"),
                            spin_up_years = 0, sdigs = 5, verbose = TRUE) {

  msg <- function(...) if (verbose) message(...)
  out_paths <- file.path(out_path, paste0("lake_", lake_id))

  msg("Writing LakeEnsemblR.yaml for ", length(lake_id), " lake(s)")
  for (i in seq_along(lake_id)) {
    set_up_config(lake_id = lake_id[i], lake_meta = lake_meta,
                  config_file = config_file, out_path = out_paths[i],
                  nc_files_met = nc_files_met)
  }

  msg("Loading meteo forcing")
  met <- lapply(unique(nc_files_met$per), function(p) {
    msg("  period ", p)
    files <- nc_files_met |> filter(per == p) |> select(path, var) |>
      pivot_wider(values_from = path, names_from = var)
    load_met_forc_multi(lake_id = lake_id, ncfiles = files, lake_meta = lake_meta)
  }) |> bind_rows() |> arrange(lake_id, datetime)

  msg("Loading hypsographs")
  hyps <- load_hypso(x_id = lake_meta$x_id[lake_id], y_id = lake_meta$y_id[lake_id],
                     ncfile = nc_file_hypso, lake_id = lake_id)

  # round forcing to sdigs significant digits
  met_cols <- setdiff(names(met), c("datetime", "lake_id"))
  met[met_cols] <- signif(met[met_cols], sdigs)
  met$datetime <- format(met$datetime, format = "%Y-%m-%d 00:00:00")

  wd <- getwd()
  on.exit(setwd(wd))

  for (i in seq_along(lake_id)) {
    msg("[", i, "/", length(lake_id), "] ", out_paths[i])

    met_i <- met[met$lake_id == paste0("lake_", lake_id[i]), ] |> select(-lake_id)
    write.csv(met_i, file.path(out_paths[i], "meteo.csv"), quote = FALSE, row.names = FALSE)

    hyps_i <- hyps[hyps$lake_id == lake_id[i], c("Depth_meter", "Area_meterSquared")]
    write.csv(signif(hyps_i, sdigs), file.path(out_paths[i], "hypsograph.csv"),
              quote = FALSE, row.names = FALSE)

    init_i <- create_init_prof(max_depth = lake_meta$depth[lake_id[i]],
                               lat = lake_meta$lat[lake_id[i]])
    write.csv(signif(init_i, sdigs), file.path(out_paths[i], "init_temp_prof.csv"),
              quote = FALSE, row.names = FALSE)

    if (spin_up_years > 0) add_spin_up(folder = out_paths[i], spin_up_years = spin_up_years)

    # model folders
    setwd(out_paths[i])
    if (verbose) {
      export_config(config_file = "LakeEnsemblR.yaml", model = models)
    } else {
      suppressMessages(export_config(config_file = "LakeEnsemblR.yaml", model = models))
    }

    # disable evaporation in GLM to avoid water loss (no in-/outflows)
    if ("GLM" %in% models) {
      nml <- read_nml(file.path("GLM", "glm3.nml"))
      nml[["debugging"]][["disable_evap"]] <- TRUE
      write_nml(nml, file.path("GLM", "glm3.nml"))
    }
    setwd(wd)
  }

  invisible(out_paths)
}
