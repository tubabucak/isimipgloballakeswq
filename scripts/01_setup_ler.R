# Step 1: LakeEnsemblR (physical) set-up for each lake

source("scripts/00_settings.R")

met_paths <- create_cdata_paths(base_dir = forcing_dir, scen = scenario, gcm = gcm)

setup_ler_lakes(lake_id       = lake_ids,
                lake_meta     = lake_meta_dat,
                config_file   = file.path(template_dir, "LakeEnsemblR.yaml"),
                out_path      = run_dir,
                nc_files_met  = met_paths,
                nc_file_hypso = hypso_nc,
                models        = ler_models,
                spin_up_years = spin_up_years)
