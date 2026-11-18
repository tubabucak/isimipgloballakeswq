# Step 2 for the 40 Danish lakes only (test of the HPC set-up)
#
#   Rscript scripts/02_run_denmark.R <task>     (or SLURM_ARRAY_TASK_ID)
#   sbatch --array=1-4 hpc/run_denmark.sh
#
# Same as 02_run_lakes.R, but the lakes are the Danish rows below (grid cells
# with data in example_climate/*_dnk_*), and the forcing is always
# example_climate/ (GSWP3-ERA5 obsclim, 1991-2000). Task k runs the k-th block
# of block_size Danish lakes (block_size = 10: tasks 1-4). Without a task
# (task 0) all 40 lakes are run. Lakes with metrics.rds are skipped.
# Log: <log_dir>/dnk_task_<k>.csv.

source("scripts/00_settings.R")

forcing_dir <- "example_climate"     # Denmark extract; NA outside Denmark

dnk_rows <- c(25472, 25473, 25474, 25475, 25476, 25477, 25478, 25479,
              25824, 25825, 25826, 25827, 25828, 25829, 25830, 25831,
              26161, 26162, 26163, 26164, 26165, 26166, 26167, 26168,
              26497, 26498, 26499, 26500, 26501, 26502, 26503, 26504,
              26849, 26850, 26851, 26852, 26853, 27197, 27198, 27199)

inflow_table <- read.csv(inflow_table_file)

args <- commandArgs(trailingOnly = TRUE)
task <- as.integer(if (length(args) > 0) args[1] else Sys.getenv("SLURM_ARRAY_TASK_ID", "0"))
rows <- if (task == 0) dnk_rows else dnk_rows[ceiling(seq_along(dnk_rows) / block_size) == task]
if (length(rows) == 0) stop("No Danish lakes for task ", task, " (tasks 1-",
                            ceiling(length(dnk_rows) / block_size), ")")

# Folders of each lake: one per scenario set
sets_of <- function(row) {
  if (inflow_table$set[row] == "default") "default" else names(nutr_scenarios)
}
lake_folder <- function(set, row) file.path(run_dir, set, paste0("lake_", row))

todo <- rows[vapply(rows, function(r) {
  !all(file.exists(file.path(lake_folder(sets_of(r), r), "metrics.rds")))
}, logical(1))]
message("Denmark task ", task, ": ", length(rows), " lakes, ", length(todo), " to run")

dir.create(log_dir, showWarnings = FALSE, recursive = TRUE)
log_file <- file.path(log_dir, sprintf("dnk_task_%02d.csv", task))
old_log <- if (file.exists(log_file)) read.csv(log_file) else NULL
if (!is.null(old_log)) old_log <- old_log[!old_log$row %in% todo, ]

if (length(todo) > 0) {
  # ---- Physical set-up, once per lake -------------------------------------
  # setup folder per task, so array tasks running at once do not collide
  setup_dir <- file.path(run_dir, sprintf("setup_dnk_%02d", task))
  met_paths <- create_cdata_paths(forcing_dir)
  setup_ler_lakes(lake_id       = todo,
                  lake_meta     = lake_meta_dat,
                  config_file   = file.path(template_dir, "LakeEnsemblR.yaml"),
                  out_path      = setup_dir,
                  nc_files_met  = met_paths,
                  nc_file_hypso = hypso_nc,
                  models        = ler_models,
                  spin_up_years = spin_up_years,
                  verbose       = FALSE)

  # ---- WQ set-up and run, per lake and scenario set -------------------------
  log <- list()
  for (r in todo) {
    src <- file.path(setup_dir, paste0("lake_", r))
    sets <- sets_of(r)
    for (s in sets) {
      d <- lake_folder(s, r)
      unlink(d, recursive = TRUE)
      dir.create(dirname(d), showWarnings = FALSE, recursive = TRUE)
      # copy for all but the last set, which takes the set-up folder itself
      # (src and d are both named lake_<row>)
      if (s != tail(sets, 1)) file.copy(src, dirname(d), recursive = TRUE) else file.rename(src, d)

      message("lake ", r, " / ", s)
      res <- run_global_lake(d, models = wq_models,
                             conc = if (s == "default") NULL else nutr_scenarios[[s]],
                             residence_time_d = inflow_table$res_time[r],
                             ler_models = ler_models, template_dir = template_dir,
                             metric_template = metric_template, layers = metric_layers,
                             clean = clean_output, wet_max_lat = wet_max_lat)
      if (!res$ok) warning("lake ", r, " / ", s, ": ", res$error, call. = FALSE)
      log[[length(log) + 1]] <- cbind(row = r, set = s, res)
      # write after every lake, so a time-out keeps the log of the lakes done
      write.csv(rbind(old_log, do.call(rbind, log)), log_file, row.names = FALSE)
    }
  }
}

if (!file.exists(log_file)) {
  message("Denmark task ", task, ": all lakes already have metrics.rds (delete them to rerun)")
  quit(save = "no")
}
log <- read.csv(log_file)
message("Denmark task ", task, ": ", sum(log$ok), "/", nrow(log), " lake runs ok")
print(log[!log$ok, c("row", "set", "models_ok", "error")])
