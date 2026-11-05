# Local test of step 2 on a multi-core computer: one Rscript process per lake
# (02_run_lakes.R with LAKE_ROWS), n_cores at a time. Each lake has its own
# folders and log, so the processes do not interfere.
#
#   Rscript scripts/run_local.R <n_cores> <row> <row> ...
#   Rscript scripts/run_local.R 30 26852 26164 34618
#
# Then step 3 as usual (Rscript scripts/03_isimip_output.R <set> <model>).
# Output of each process: logs/local_<row>.out

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) stop("Usage: Rscript scripts/run_local.R <n_cores> <row> ...")
n_cores <- as.integer(args[1])
rows    <- as.integer(args[-1])

rscript <- file.path(R.home("bin"), "Rscript")
dir.create("logs", showWarnings = FALSE)

cl <- parallel::makeCluster(min(n_cores, length(rows)))
status <- parallel::parLapplyLB(cl, rows, function(r, rscript) {
  Sys.setenv(LAKE_ROWS = r)   # inherited by the Rscript process
  system2(rscript, "scripts/02_run_lakes.R",
          stdout = sprintf("logs/local_%d.out", r), stderr = sprintf("logs/local_%d.out", r))
}, rscript = rscript)
parallel::stopCluster(cl)

data.frame(row = rows, exit = unlist(status))
