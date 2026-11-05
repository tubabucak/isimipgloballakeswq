# Helpers for setting up and running LakeEnsemblR.WQ in the ISIMIP lake folders

#' Copy the WQ templates into each lake folder
#'
#' set_up_lake_multiple() only copies LakeEnsemblR.yaml, so the WQ config,
#' the metrics file and the parameter files are copied here. par_file paths
#' are resolved relative to the lake folder, so the par_*.csv files go into
#' <lake>/initial_pars/.
copy_wq_templates <- function(lake_dirs, template_dir = "templates",
                              files = c("LakeEnsemblR_WQ.yaml", "Output.yaml"),
                              par_dir = "initial_pars",
                              overwrite = TRUE) {
  src <- file.path(template_dir, files)
  missing <- src[!file.exists(src)]
  if (length(missing) > 0) stop("Template(s) not found: ", paste(missing, collapse = ", "))
  par_files <- list.files(par_dir, pattern = "^par_.*\\.csv$", full.names = TRUE)
  if (length(par_files) == 0) stop("No par_*.csv files found in ", par_dir)
  for (d in lake_dirs) {
    if (!dir.exists(d)) stop("Lake folder not found: ", d)
    file.copy(src, d, overwrite = overwrite)
    dir.create(file.path(d, "initial_pars"), showWarnings = FALSE)
    file.copy(par_files, file.path(d, "initial_pars"), overwrite = overwrite)
  }
  invisible(lake_dirs)
}

#' Run a function for each lake folder, logging failures instead of stopping
#'
#' Returns a data.frame with one row per folder: ok (TRUE/FALSE) and the
#' error message for failed lakes.
for_each_lake <- function(lake_dirs, fun, ..., verbose = TRUE) {
  res <- lapply(seq_along(lake_dirs), function(i) {
    d <- lake_dirs[i]
    if (verbose) message("[", i, "/", length(lake_dirs), "] ", d)
    out <- tryCatch({ fun(d, ...); "" }, error = function(e) conditionMessage(e))
    if (nzchar(out)) warning(d, ": ", out, call. = FALSE)
    data.frame(folder = d, ok = !nzchar(out), error = out)
  })
  do.call(rbind, res)
}

#' Set up WQ for one lake folder (after set_up_lake_multiple())
setup_wq_lake <- function(folder, config_file = "LakeEnsemblR_WQ.yaml", verbose = FALSE) {
  export_config_wq(config_file, folder = folder, verbose = verbose)
}

#' Run the WQ models for one lake folder
run_wq_lake <- function(folder, models, config_file = "LakeEnsemblR_WQ.yaml", verbose = FALSE) {
  res <- run_ensemble_wq(config_file, models = models, folder = folder,
                         verbose = verbose, on_error = "skip")
  failed <- models[!toupper(models) %in% toupper(res$successful_models)]
  if (length(failed) > 0) stop("model(s) failed: ", paste(failed, collapse = ", "))
  invisible(res)
}

#' Cap the latitude of a GOTM model (default GOTM-WET) at +-max_lat
#'
#' WET fails with polar day/night, so polar lakes are run at the polar
#' circle. Only <folder>/<model>/gotm.yaml is changed; the line is edited in
#' place to keep the comments.
#' @returns TRUE if the latitude was changed
cap_gotm_latitude <- function(folder, max_lat, model = "GOTM-WET") {
  f <- file.path(folder, model, "gotm.yaml")
  x <- readLines(f)
  i <- grep("^\\s+latitude:", x)[1]
  lat <- as.numeric(sub("^\\s+latitude:\\s*([-0-9.eE+]+).*", "\\1", x[i]))
  if (is.na(lat) || abs(lat) <= max_lat) return(FALSE)
  x[i] <- sub("(latitude:\\s*)[-0-9.eE+]+", paste0("\\1", sign(lat) * max_lat), x[i])
  writeLines(x, f)
  TRUE
}

#' Set up, run and summarise one lake folder of the global runs
#'
#' Copies the WQ templates, adds the generic inflow (unless `conc` is NULL),
#' runs the WQ models and saves the cal_metrics() result of the models that
#' ran to <folder>/metrics.rds, which create_isimip_global() reads instead of
#' the model output (column `rds`). With `clean = TRUE` everything in the
#' folder except metrics.rds (set-up, forcing, model output) is deleted
#' afterwards; 02_run_lakes.R sets up again any lake without metrics.rds.
#'
#' @param folder Lake folder from setup_ler_lakes()
#' @param conc Inflow concentrations (see add_generic_inflow()); NULL = no inflow
#' @param residence_time_d Residence time for the inflow (days)
#' @param metric_template Metrics file in `template_dir`, copied to
#'   <folder>/Output.yaml (fewer metrics = faster cal_metrics())
#' @param layers Passed to cal_metrics(): "profile" or "epi_hypo" (daily
#'   epilimnion/hypolimnion means only, a much smaller metrics.rds)
#' @param wet_max_lat |latitude| cap for GOTM-WET (see cap_gotm_latitude());
#'   NULL = no cap
#' @returns One-row data.frame: folder, ok, models_ok (comma-separated), error
run_global_lake <- function(folder, models, conc = NULL, residence_time_d = NULL,
                            ler_models = c("GLM", "GOTM", "Simstrat"),
                            template_dir = "templates", metric_template = "Output.yaml",
                            layers = "profile", clean = FALSE, wet_max_lat = NULL) {
  models_ok <- character()
  err <- tryCatch({
    copy_wq_templates(folder, template_dir)
    file.copy(file.path(template_dir, metric_template), file.path(folder, "Output.yaml"),
              overwrite = TRUE)
    if (!is.null(conc)) {
      add_generic_inflow(folder, residence_time_d = residence_time_d, conc = conc,
                         models = ler_models)
    }
    setup_wq_lake(folder)
    if (!is.null(wet_max_lat) && "GOTM-WET" %in% models) {
      cap_gotm_latitude(folder, wet_max_lat)
    }
    res <- run_ensemble_wq("LakeEnsemblR_WQ.yaml", models = models, folder = folder,
                           verbose = FALSE, on_error = "skip")
    models_ok <- res$successful_models
    if (length(models_ok) == 0) stop("all models failed")

    # cal_metrics() model names (GLM, WET, ...) are the model_folders keys
    out_yaml <- yaml::read_yaml(file.path(folder, "Output.yaml"))
    keys <- names(out_yaml$model_folders)
    keys_ok <- keys[vapply(out_yaml$model_folders, function(p) {
      any(toupper(models_ok) == toupper(dirname(p)))
    }, logical(1))]
    wd <- setwd(folder)
    on.exit(setwd(wd), add = TRUE)
    # cal_metrics() takes "all" or a single model (a vector fails), so models
    # that ran are merged one by one when some failed
    cm <- function(filter) {
      res <- NULL
      utils::capture.output(res <- suppressWarnings(suppressMessages(
        cal_metrics(metric_yaml_file = "Output.yaml", model_filter = filter,
                    wq_config_file = "LakeEnsemblR_WQ.yaml", layers = layers))))
      res
    }
    metrics <- if (setequal(keys_ok, keys)) cm("all") else Reduce(utils::modifyList, lapply(keys_ok, cm))
    saveRDS(metrics, "metrics.rds")
    setwd(wd)
    models_ok <- keys_ok
    if (clean) {
      rest <- list.files(folder, all.files = TRUE, no.. = TRUE)
      unlink(file.path(folder, setdiff(rest, "metrics.rds")), recursive = TRUE)
    }
    ""
  }, error = function(e) conditionMessage(e))
  data.frame(folder = folder, ok = !nzchar(err) && length(models_ok) > 0,
             models_ok = paste(models_ok, collapse = ","), error = err)
}
