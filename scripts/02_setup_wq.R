# Step 2: convert the LakeEnsemblR folders to LakeEnsemblR.WQ

source("scripts/00_settings.R")

copy_wq_templates(lake_dirs, template_dir)

setup_log <- for_each_lake(lake_dirs, setup_wq_lake)
write.csv(setup_log, file.path(run_dir, "log_setup_wq.csv"), row.names = FALSE)
print(setup_log[!setup_log$ok, ])
