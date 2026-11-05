# Step 1 (once): residence time and scenario set of every lake
#
# Lakes with HydroLAKES discharge get a generic inflow in the nutrient
# scenarios (residence time clamped to 7 d - 100 yr); lakes without discharge
# or without data get no inflow and are run once as "default".

source("scripts/00_settings.R")

inflow_table <- make_inflow_table(lake_meta_dat)
write.csv(inflow_table, inflow_table_file, row.names = FALSE)

print(table(inflow_table$set, inflow_table$flag))
message("Array tasks (", block_size, " lakes each): 1-",
        ceiling(nrow(inflow_table) / block_size))
