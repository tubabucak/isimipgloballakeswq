# Step 2 (HPC array task): set up and run one block of lakes
#
#   Rscript scripts/02_run_lakes.R <task>     (or SLURM_ARRAY_TASK_ID + TASK_OFFSET)
#
# TASK_OFFSET (default 0) is added to the array index, for clusters that
# limit array indices (e.g. to 1000): --array=1-1000 with TASK_OFFSET=1000
# runs tasks 1001-2000. Task k runs rows (k-1)*block_size+1 ... k*block_size of lake_meta_dat. The
# physical set-up (forcing, hypsograph, spin-up) is made once per lake and
# then moved to <run_dir>/default/ (no inflow) or copied to
# <run_dir>/lownutr/ and <run_dir>/highnutr/ (generic inflow). Lakes that
# already have metrics.rds in all their folders are skipped, so a task can be
# resubmitted after a time-out. Log: <log_dir>/task_<k>.csv.
#
# For a test, set LAKE_ROWS to a comma-separated list of rows (log:
# task_test_<rows>.csv); scripts/run_local.R runs such tests in parallel.

source("scripts/00_settings.R")

inflow_table <- read.csv(inflow_table_file)

args <- commandArgs(trailingOnly = TRUE)
task <- as.integer(if (length(args) > 0) args[1] else Sys.getenv("SLURM_ARRAY_TASK_ID", "0")) +
  as.integer(Sys.getenv("TASK_OFFSET", "0"))
if (nzchar(Sys.getenv("LAKE_ROWS"))) {
  rows <- as.integer(strsplit(Sys.getenv("LAKE_ROWS"), ",")[[1]])
  task <- 0L
} else {
  rows <- inflow_table$row[ceiling(inflow_table$row / block_size) == task]
}
if (length(rows) == 0) stop("No lakes for task ", task)

# Folders of each lake: one per scenario set
sets_of <- function(row) {
  if (inflow_table$set[row] == "default") "default" else names(nutr_scenarios)
}
lake_folder <- function(set, row) file.path(run_dir, set, paste0("lake_", row))

todo <- rows[vapply(rows, function(r) {
  !all(file.exists(file.path(lake_folder(sets_of(r), r), "metrics.rds")))
}, logical(1))]
message("Task ", task, ": ", length(rows), " lakes, ", length(todo), " to run")

dir.create(log_dir, showWarnings = FALSE, recursive = TRUE)
# tests get a log per set of rows, so several can run at once (run_local.R)
log_file <- file.path(log_dir, if (task == 0) paste0("task_test_", paste(rows, collapse = "-"), ".csv")
                      else sprintf("task_%04d.csv", task))
old_log <- if (file.exists(log_file)) read.csv(log_file) else NULL
if (!is.null(old_log)) old_log <- old_log[!old_log$row %in% todo, ]

if (length(todo) > 0) {
  # ---- Physical set-up, once per lake -------------------------------------
  setup_dir <- file.path(run_dir, "setup")
  met_paths <- create_cdata_paths(forcing_dir, climate, forcing)
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
  message("Task ", task, ": all lakes already have metrics.rds (delete them to rerun)")
  quit(save = "no")
}
log <- read.csv(log_file)
message("Task ", task, ": ", sum(log$ok), "/", nrow(log), " lake runs ok")
print(log[!log$ok, c("row", "set", "models_ok", "error")])
