# Mean depth of the ISIMIP3 representative lakes (GLOBathy + HydroLAKES)
# versus HydroLAKES Depth_avg, for Denmark and the whole world.
# Run from the isimipgloballerwq project root.

library(ncdf4)
library(dplyr)
library(ggplot2)

isimip_dir <- "../ISIMIP4"
load("data/lake_meta_dat.rda")
hl <- read.csv("data/hydrolakes_attributes_all.csv")
hl[hl == -9999] <- NA

# Value of a lon x lat netcdf variable in each lake's grid cell
read_cell <- function(file, var) {
  nc <- nc_open(file)
  on.exit(nc_close(nc))
  ncvar_get(nc, var)[cbind(lake_meta_dat$x_id, lake_meta_dat$y_id)]
}

# Danish cells = non-missing cells of the Denmark-masked climate file
dnk_tas <- function(file) {
  nc <- nc_open(file)
  on.exit(nc_close(nc))
  ncvar_get(nc, "tas", count = c(-1, -1, 1))
}
tas <- dnk_tas("example_climate/gswp3-era5_obsclim_tas_dnk_30arcmin_daily_1991_2000.nc")

h <- hl[match(lake_meta_dat$hydrolakes, hl$Hylak_id), ]
depths <- data.frame(id          = lake_meta_dat$id,
                     area        = lake_meta_dat$area,
                     mean_isimip = read_cell(file.path(isimip_dir, "mean_lakedepth.nc"), "mean_lakedepth"),
                     mean_hl     = h$Depth_avg,
                     denmark     = !is.na(tas[cbind(lake_meta_dat$x_id, lake_meta_dat$y_id)])) |>
  filter(!is.na(mean_isimip), !is.na(mean_hl), mean_hl > 0)

# Both panels: world (all lakes) and Denmark
plot_dat <- bind_rows(mutate(depths, region = "World"),
                      mutate(filter(depths, denmark), region = "Denmark")) |>
  mutate(region = factor(region, levels = c("World", "Denmark")))

# Number of lakes and median ISIMIP/HydroLAKES ratio per panel
stats <- plot_dat |>
  group_by(region) |>
  summarise(n = n(), ratio = median(mean_isimip / mean_hl), .groups = "drop") |>
  mutate(label = sprintf("n = %d\nmedian ISIMIP/HydroLAKES = %.2f", n, ratio))
print(stats)


p <- ggplot(plot_dat, aes(mean_hl, mean_isimip)) +
  geom_point(aes(size = region == "Denmark"), alpha = 0.3, colour = "steelblue4", show.legend = FALSE) +
  scale_size_manual(values = c(`FALSE` = 0.3, `TRUE` = 2)) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed") +
#  geom_text(data = stats, aes(label = label), x = -Inf, y = Inf,
 #           hjust = -0.05, vjust = 1.2, size = 3.2) +
  scale_x_log10(breaks = c(0.1, 1, 10, 100, 1000), labels = scales::label_number(drop0trailing = TRUE)) +
  scale_y_log10(breaks = c(0.1, 1, 10, 100, 1000), labels = scales::label_number(drop0trailing = TRUE)) +

  facet_wrap(~region) +
  labs(x = "HydroLAKES mean depth (m)", y = "ISIMIP mean depth (m)") +
  theme_bw()
print(p)
