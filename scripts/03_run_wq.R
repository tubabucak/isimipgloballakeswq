# Step 3: run the coupled WQ models for each lake

source("scripts/00_settings.R")

run_log <- for_each_lake(lake_dirs, run_wq_lake, models = wq_models)
write.csv(run_log, file.path(run_dir, "log_run_wq.csv"), row.names = FALSE)
print(run_log[!run_log$ok, ])
