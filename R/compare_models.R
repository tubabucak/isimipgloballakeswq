# Compare the WQ models using the ISIMIP lakes_global files
# (same variables, units and epilimnion/hypolimnion levels for all models)

#' Read ISIMIP lakes_global files at the lakes' grid cells
#'
#' @param isimip_dir Folder with the files written by create_isimip_global()
#' @param lakes data.frame with `id`, `lat` and `lon` (as passed to
#'   create_isimip_global())
#' @param vars Variables to read, e.g. c("chl", "do"); NULL = all
#' @param models Models to read, e.g. c("glm-aed", "gotm-wet"); NULL = all
#' @returns Long data.frame: model, var, units, lake, level ("epi"/"hypo"),
#'   date, value (NA where the model has no data)
read_isimip_lakes <- function(isimip_dir, lakes, vars = NULL, models = NULL) {
  files <- list.files(isimip_dir, pattern = "_global_daily_[0-9]{4}_[0-9]{4}[.]nc$",
                      full.names = TRUE)
  info <- data.frame(path  = files,
                     model = sub("_.*", "", basename(files)),
                     var   = sub(".*_([^_]+)_global_daily_.*", "\\1", basename(files)))
  if (!is.null(vars)) info <- info[info$var %in% vars, ]
  info <- info[keep_models(info$model, models), ]
  if (nrow(info) == 0) stop("No ISIMIP files found in ", isimip_dir)

  # centre of the 0.5 degree cell a coordinate falls in
  cell_centre <- function(x) floor(x / 0.5) * 0.5 + 0.25

  res <- lapply(seq_len(nrow(info)), function(i) {
    nc <- nc_open(info$path[i])
    on.exit(nc_close(nc))
    x_id <- match(cell_centre(lakes$lon), ncvar_get(nc, "lon"))
    y_id <- match(cell_centre(lakes$lat), ncvar_get(nc, "lat"))
    if (anyNA(x_id) || anyNA(y_id)) stop("Lake(s) outside the grid of ", basename(info$path[i]))
    date <- as.Date(sub("days since ", "", ncatt_get(nc, "time", "units")$value)) +
      ncvar_get(nc, "time")
    units <- ncatt_get(nc, info$var[i], "units")$value

    lapply(seq_len(nrow(lakes)), function(k) {
      v <- matrix(ncvar_get(nc, info$var[i], start = c(x_id[k], y_id[k], 1, 1),
                            count = c(1, 1, 2, -1)), nrow = 2)
      data.frame(model = info$model[i], var = info$var[i], units = units,
                 lake = lakes$id[k], level = rep(c("epi", "hypo"), each = ncol(v)),
                 date = rep(date, 2), value = c(v[1, ], v[2, ]))
    })
  })
  bind_rows(unlist(res, recursive = FALSE))
}

#' Epilimnion/hypolimnion water temperature from the model output
#'
#' Water temperature is not an ISIMIP lakes_global WQ variable, so it is read
#' with cal_metrics() and split at the daily thermocline in the same way as
#' create_isimip_global() does for the WQ variables.
#' @param lakes data.frame with `id` and `folder` (as passed to
#'   create_isimip_global())
#' @param models LakeEnsemblR.WQ model keys, e.g. c("GLM", "WET")
#' @returns Long data.frame like read_isimip_lakes() (var = "temp"), with the
#'   ISIMIP model names
read_temp_epi_hypo <- function(lakes, models) {
  wq <- asNamespace("LakeEnsemblR.WQ")
  res <- list()
  for (k in seq_len(nrow(lakes))) for (m in toupper(models)) {
    metrics <- wq$.isimip_lake_metrics(lakes[k, ], m, "Output.yaml", "LakeEnsemblR_WQ.yaml")
    temp <- wq$.isimip_profiles(metrics, "Temp_degreeCelcius", m)
    if (is.null(temp)) next
    eh <- wq$.isimip_epi_hypo(temp[[1]], wq$.isimip_thermocline(temp[[1]]))
    date <- as.Date(rownames(eh))
    res[[paste(k, m)]] <- data.frame(model = wq$.isimip_model_names[[m]], var = "temp",
                                     units = "degC", lake = lakes$id[k],
                                     level = rep(c("epi", "hypo"), each = nrow(eh)),
                                     date = rep(date, 2), value = c(eh[, "epi"], eh[, "hypo"]))
  }
  bind_rows(res)
}

#' Which models to keep (case-insensitive); NULL keeps all
keep_models <- function(model, models = NULL) {
  if (is.null(models)) return(rep(TRUE, length(model)))
  unknown <- setdiff(tolower(models), tolower(model))
  if (length(unknown) > 0) {
    warning("Model(s) not found: ", paste(unknown, collapse = ", "),
            ". Available: ", paste(unique(model), collapse = ", "), call. = FALSE)
  }
  tolower(model) %in% tolower(models)
}

#' Statistics per lake, variable, level and model
#'
#' Mean, sd, min and max over the days, and bias and RMSD against the
#' ensemble mean (mean over the models with data on that day).
#' @param df Output of read_isimip_lakes()
#' @param models Models to include; NULL = all. The ensemble mean is taken
#'   over the selected models only.
summarise_model_comparison <- function(df, models = NULL) {
  df[keep_models(df$model, models), ] |>
    filter(!is.na(value)) |>
    group_by(lake, var, level, date) |>
    mutate(ens_mean = mean(value), n_models = n()) |>
    group_by(lake, var, units, level, model) |>
    summarise(n_days = n(),
              mean   = mean(value),
              sd     = sd(value),
              min    = min(value),
              max    = max(value),
              bias   = mean(value - ens_mean),
              rmsd   = sqrt(mean((value - ens_mean)^2)),
              .groups = "drop")
}

#' Time series of all models for one lake
#'
#' @param df Output of read_isimip_lakes()
#' @param lake Lake id to plot (default: the first one)
#' @param vars Variables to plot; NULL = all
#' @param levels "epi" and/or "hypo"
#' @param models Models to plot; NULL = all
#' @returns A ggplot (variables in rows, levels in columns)
plot_model_comparison <- function(df, lake = df$lake[1], vars = NULL,
                                  levels = c("epi", "hypo"), models = NULL) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) stop("Package 'ggplot2' is needed")
  d <- df[df$lake == lake & df$level %in% levels & !is.na(df$value) &
            keep_models(df$model, models), ]
  if (!is.null(vars)) d <- d[d$var %in% vars, ]
  if (nrow(d) == 0) stop("No data for lake ", lake)
  d$panel <- paste0(d$var, " (", d$units, ")")

  ggplot2::ggplot(d, ggplot2::aes(x = date, y = value, colour = model)) +
    ggplot2::geom_line(linewidth = 0.3) +
    ggplot2::facet_grid(panel ~ level, scales = "free_y") +
    ggplot2::labs(x = NULL, y = NULL, colour = "Model", title = lake) +
    ggplot2::theme_bw()
}
