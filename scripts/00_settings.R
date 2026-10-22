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

# ---- ISIMIP forcing -------------------------------------------------------
forcing_dir <- "path/to/ISIMIP/climate"    # contains <scenario>/<gcm>/*.nc
hypso_nc    <- "../ISIMIP4/hypso_area.nc"  # ISIMIP hypsograph file (area, levels)
scenario    <- "historical"
gcm         <- "gfdl-esm4"

# ---- Lakes ----------------------------------------------------------------
load("data/lake_meta_dat.rda")              # from ISIMIPglobalLER
lake_ids <- 1:3                             # rows of lake_meta_dat; start small

# ---- Simulation -----------------------------------------------------------
spin_up_years <- 10
ler_models    <- c("GLM", "GOTM", "Simstrat")   # physical models to export
wq_models     <- c("GLM-AED", "GOTM-WET", "GOTM-Selmaprotbas", "Simstrat-AED2")
isimip_models <- c("GLM", "WET", "SELMAPROTBAS", "SIMSTRAT")  # names for create_isimip_global()

# Years written to the ISIMIP files (excludes spin-up)
sim_years <- switch(scenario,
                    picontrol  = c(1850, 2100),
                    historical = c(1850, 2014),
                    ssp126     = c(2015, 2100),
                    ssp370     = c(2015, 2100),
                    ssp585     = c(2015, 2100))

# ---- Folders --------------------------------------------------------------
template_dir <- "templates"
run_dir      <- file.path("runs", scenario, gcm)
out_dir      <- file.path("isimip_global", scenario, gcm)
lake_dirs    <- file.path(run_dir, paste0("lake_", lake_ids))

# ---- ISIMIP file attributes -----------------------------------------------
isimip_info <- list(forcing          = gcm,
                    climate_scenario = scenario,
                    time_ref         = "1601-01-01",   # ISIMIP3b
                    contact          = "Tuba Bucak <tbo@ecos.au.dk>",
                    institution      = "Aarhus University")
