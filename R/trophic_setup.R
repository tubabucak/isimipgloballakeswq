# Trophic-state presets: same model parameters, different nutrient forcing
#
# Inflow concentrations are chosen so that, with a residence time of ~1 year,
# the expected in-lake concentrations hit the target (Vollenweider-type
# retention: TP_lake ~ TP_in / (1 + sqrt(tau)), TN retention ~30-40%).
# Initial water-column nutrients are set near the expected in-lake values to
# shorten the spin-up. All concentrations in g m-3 as element (P, N, Si).

trophic_presets <- list(
  # target in-lake: TP ~0.010, TN ~0.35
  oligotrophic = list(inflow = c(PO4 = 0.008, POP = 0.012, NH4 = 0.02,
                                 NO3 = 0.48, Silica = 2.0),          # TP 0.020, TN 0.50
                      init   = c(PO4 = 0.004, NH4 = 0.01, NO3 = 0.25)),
  # target in-lake: TP >0.100, TN >1.2
  eutrophic    = list(inflow = c(PO4 = 0.150, POP = 0.100, NH4 = 0.10,
                                 NO3 = 1.90, Silica = 2.0),          # TP 0.250, TN 2.00
                      init   = c(PO4 = 0.060, NH4 = 0.08, NO3 = 1.10))
)

#' Set the initial water-column PO4, NH4 and NO3 of all WQ models
#'
#' Edits <folder>/initial_pars/par_phosphorus.csv and par_nitrogen.csv (run
#' after copy_wq_templates() and before setup_wq_lake()). Rows missing from
#' the trimmed par files are taken from `full_dir`.
#' @param init Named vector (PO4, NH4, NO3) in g m-3 as element
set_initial_nutrients <- function(folder, init, full_dir = "initial_pars/full") {
  mmol <- c(PO4 = 1000 / 30.974, NH4 = 1000 / 14.007, NO3 = 1000 / 14.007)
  # path in the par file -> (nutrient, factor from g m-3 to the model unit)
  targets <- list(
    par_phosphorus.csv = rbind(
      c("abiotic_water/initialization/sPO4W", "PO4", 1),
      c("selmaprotbas/initialization/po",     "PO4", mmol[["PO4"]]),
      c("aed2_phosphorus/frp_initial",        "PO4", mmol[["PO4"]])),
    par_nitrogen.csv = rbind(
      c("abiotic_water/initialization/sNH4W", "NH4", 1),
      c("abiotic_water/initialization/sNO3W", "NO3", 1),
      c("selmaprotbas/initialization/aa",     "NH4", mmol[["NH4"]]),
      c("selmaprotbas/initialization/nn",     "NO3", mmol[["NO3"]]),
      c("aed2_nitrogen/amm_initial",          "NH4", mmol[["NH4"]]),
      c("aed2_nitrogen/nit_initial",          "NO3", mmol[["NO3"]])))

  for (f in names(targets)) {
    par_file <- file.path(folder, "initial_pars", f)
    par  <- read.csv(par_file, colClasses = "character")
    full <- read.csv(file.path(full_dir, f), colClasses = "character")
    tg <- targets[[f]]
    for (k in seq_len(nrow(tg))) {
      i <- which(par$path == tg[k, 1])
      if (length(i) == 0) {
        par <- rbind(par, full[full$path == tg[k, 1], names(par)])
        i <- which(par$path == tg[k, 1])
      }
      par$value[i] <- signif(init[[tg[k, 2]]] * as.numeric(tg[k, 3]), 4)
    }
    write.csv(par, par_file, row.names = FALSE)
  }
  invisible(folder)
}
