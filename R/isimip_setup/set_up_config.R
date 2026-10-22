# Copied from ISIMIPglobalLER (github: isimipgloballer, commit a8d9608),
# author Johannes Feldbauer, GPL (>= 3).
# Changes: stop date is the last day of the last year (was 1 January of the
# last year, which dropped the last year); config file is always named
# LakeEnsemblR.yaml in the lake folder.

#' Set lake-specific values in the LakeEnsemblR yaml
#'
#' @param lake_id Id of the lake (row of `lake_meta`)
#' @param config_file Path to the template LakeEnsemblR.yaml
#' @param out_path Lake folder
#' @param nc_files_met Output of `create_cdata_paths()` (for start/end years)
set_up_config <- function(lake_id, lake_meta, config_file, out_path,
                          nc_files_met, verbose = FALSE) {

  # get some info
  max_depth <- lake_meta$depth[lake_id]
  lat <- lake_meta$lat[lake_id]
  lon <- lake_meta$lon[lake_id]
  elev <- lake_meta$elevation[lake_id]
  name <- lake_meta$id[lake_id]

  # Determine start and end date of run (before spin-up)
  periods <- unique(nc_files_met$per)
  the_years <- as.numeric(unlist(strsplit(periods, "_")))
  start_date <- paste0(min(the_years), "-01-01 00:00:00")
  end_date <- paste0(max(the_years), "-12-31 00:00:00")

  if(!dir.exists(out_path)) {
    dir.create(out_path, recursive = TRUE)
  }

  # copy config file to folder
  yaml_file <- file.path(out_path, "LakeEnsemblR.yaml")
  file.copy(config_file, yaml_file, overwrite = TRUE)

  set_val <- function(..., value) {
    input_yaml_multiple(file = yaml_file, ..., value = value, verbose = verbose)
  }

  set_val(key1 = "time", key2 = "start", value = start_date)
  set_val(key1 = "time", key2 = "stop", value = end_date)
  set_val(key1 = "location", key2 = "name", value = name)
  set_val(key1 = "location", key2 = "depth", value = max_depth)
  set_val(key1 = "location", key2 = "init_depth", value = max_depth)
  set_val(key1 = "location", key2 = "elevation", value = elev)
  set_val(key1 = "location", key2 = "latitude", value = lat)
  set_val(key1 = "location", key2 = "longitude", value = lon)

  ## change output depths
  # determine number of layers
  output_res <- case_when(max_depth <= 2 ~ 0.25,
                          max_depth > 2 & max_depth <= 20 ~ 0.5,
                          max_depth > 20 & max_depth <= 50 ~ 1.0,
                          max_depth > 50 & max_depth <= 100 ~ 2.0,
                          max_depth > 100 & max_depth <= 300 ~ 5.0,
                          max_depth > 300 ~ 10.0)
  num_layers <-  ceiling(max_depth / output_res)
  set_val(key1 = "model_parameters", key2 = "GOTM", key3 = "nlev", value = num_layers)
  set_val(key1 = "model_parameters", key2 = "Simstrat", key3 = "Grid", value = num_layers)
  set_val(key1 = "output", key2 = "depths", value = output_res)

  # set light extinction using Hakanson function (Aquatic Sciences, 1995)
  extinc_coef <- round(1.1925 * max_depth^(-0.424), 3L)
  set_val(key1 = "input", key2 = "light", key3 = "Kw", key4 = "all",
          value = extinc_coef)
}
