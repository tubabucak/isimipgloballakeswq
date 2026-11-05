# Settings shared by all steps. Source this at the top of every script.

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(lubridate)
  library(readr)
  library(ncdf4)
  library(zoo)
  library(glmtools)
  library(LakeEnsemblR)      # export_config_wq() needs LakeEnsemblR attached
  library(LakeEnsemblR.WQ)
})

invisible(lapply(list.files("R", pattern = "\\.[Rr]$", full.names = TRUE,
                            recursive = TRUE), source))

# ---- Climate forcing ------------------------------------------------------
# ISIMIP3a: <forcing_dir>/<climate>/<forcing>/*_daily_<start>_<end>.nc
forcing_dir <- Sys.getenv("ISIMIP_FORCING_DIR", "path/to/ISIMIP/climate")
hypso_nc    <- Sys.getenv("ISIMIP_HYPSO_NC", "../ISIMIP4/hypso_area.nc")  # ISIMIP hypsograph file (area, levels)
climate     <- "obsclim"
forcing     <- "gswp3-era5"

# ---- Lakes ----------------------------------------------------------------
load("data/lake_meta_dat.rda")              # from ISIMIPglobalLER
inflow_table_file <- "data/inflow_table.csv"  # from scripts/01_inflow_table.R
block_size  <- 10                           # lakes per HPC array task (~15 h each, full period)

# ---- Simulation -----------------------------------------------------------
spin_up_years <- 10                         # first 10 forcing years repeated once
ler_models    <- c("GLM", "GOTM", "Simstrat")   # physical models to export
wq_models     <- c("GLM-AED", "GOTM-WET", "GOTM-Selmaprotbas", "Simstrat-AED2")
isimip_models <- c("GLM", "WET", "SELMAPROTBAS", "SIMSTRAT")  # names for create_isimip_global()
clean_output  <- TRUE                       # keep only metrics.rds in a lake folder once saved
metric_template  <- "Output_global.yaml"    # metrics computed per lake (templates/)
metric_layers    <- "epi_hypo"              # metrics.rds holds epi/hypo means, not profiles
isimip_variables <- c("watertemp", "do", "tp", "tn", "chl", "zoobio")  # ISIMIP files written in step 3
wet_max_lat   <- 66.5                       # |latitude| cap in GOTM-WET's gotm.yaml (WET fails
                                            # with polar day/night, beyond 66.56); NULL = no cap

# Inflow concentrations (g m-3 as element) of the nutrient scenarios; same
# initial conditions (initial_pars/) in all. Lakes without discharge are run
# once without inflow as "default".
nutr_scenarios <- list(lownutr  = trophic_presets$oligotrophic$inflow,
                       highnutr = trophic_presets$eutrophic$inflow)

# ---- Folders --------------------------------------------------------------
template_dir <- "templates"
run_dir      <- file.path("runs", climate, forcing)        # <run_dir>/<set>/lake_<row>
out_dir      <- file.path("isimip_global", climate, forcing)
log_dir      <- file.path(run_dir, "logs")

# ---- ISIMIP file attributes -----------------------------------------------
# sens_scenario is set per set (lownutr, highnutr, default) in step 3
isimip_info <- list(forcing          = forcing,
                    climate_scenario = climate,
                    soc_scenario     = "histsoc",
                    time_ref         = "1901-01-01",   # ISIMIP3a; 1601-01-01 for ISIMIP3b
                    contact          = "Tuba Bucak <tbo@ecos.au.dk>",
                    institution      = "Aarhus University")
