# Compare the WQ models using the ISIMIP lakes_global files
# (same variables, units and epilimnion/hypolimnion levels for all models)

#' Read ISIMIP lakes_global files at the lakes' grid cells
#'
#' @param isimip_dir Folder with the files written by create_isimip_global()
#' @param lakes data.frame with `id`, `lat` and `lon` (as passed to
#'   create_isimip_global())
#' @param vars Variables to read, e.g. c("chl", "do"); NULL = all
#' @returns Long data.frame: model, var, units, lake, level ("epi"/"hypo"),
#'   date, value (NA where the model has no data)
read_isimip_lakes <- function(isimip_dir, lakes, vars = NULL) {
  files <- list.files(isimip_dir, pattern = "_global_daily_[0-9]{4}_[0-9]{4}[.]nc$",
                      full.names = TRUE)
  info <- data.frame(path  = files,
                     model = sub("_.*", "", basename(files)),
                     var   = sub(".*_([^_]+)_global_daily_.*", "\\1", basename(files)))
  if (!is.null(vars)) info <- info[info$var %in% vars, ]
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

#' Statistics per lake, variable, level and model
#'
#' Mean, sd, min and max over the days, and bias and RMSD against the
#' ensemble mean (mean over the models with data on that day).
#' @param df Output of read_isimip_lakes()
summarise_model_comparison <- function(df) {
  df |>
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
#' @returns A ggplot (variables in rows, levels in columns)
plot_model_comparison <- function(df, lake = df$lake[1], vars = NULL,
                                  levels = c("epi", "hypo")) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) stop("Package 'ggplot2' is needed")
  d <- df[df$lake == lake & df$level %in% levels & !is.na(df$value), ]
  if (!is.null(vars)) d <- d[d$var %in% vars, ]
  if (nrow(d) == 0) stop("No data for lake ", lake)
  d$panel <- paste0(d$var, " (", d$units, ")")

  ggplot2::ggplot(d, ggplot2::aes(x = date, y = value, colour = model)) +
    ggplot2::geom_line(linewidth = 0.3) +
    ggplot2::facet_grid(panel ~ level, scales = "free_y") +
    ggplot2::labs(x = NULL, y = NULL, colour = "Model", title = lake) +
    ggplot2::theme_bw()
}
