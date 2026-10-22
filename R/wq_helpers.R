# Helpers for setting up and running LakeEnsemblR.WQ in the ISIMIP lake folders

#' Copy the WQ templates into each lake folder
#'
#' set_up_lake_multiple() only copies LakeEnsemblR.yaml, so the WQ config,
#' the metrics file and any parameter files are copied here.
copy_wq_templates <- function(lake_dirs, template_dir = "templates",
                              files = c("LakeEnsemblR_WQ.yaml", "Output.yaml"),
                              overwrite = TRUE) {
  src <- file.path(template_dir, files)
  missing <- src[!file.exists(src)]
  if (length(missing) > 0) stop("Template(s) not found: ", paste(missing, collapse = ", "))
  for (d in lake_dirs) {
    if (!dir.exists(d)) stop("Lake folder not found: ", d)
    file.copy(src, d, overwrite = overwrite)
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
