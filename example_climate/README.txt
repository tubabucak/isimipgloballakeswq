Climate forcing for the Danish test lakes: GSWP3-ERA5 obsclim, 1991-2000,
cut to Denmark from the global ISIMIP files. The folder holds 8 variables:
tas, hurs, pr, prsn, ps, rlds, rsds, sfcwind.

The files were made with cdo, with this command for each variable (shown
for tas):

cdo -f nc4c -z zip_5 -L -ifthen -selname,m_DNK countrymasks-binary_30arcmin.nc gswp3-era5_obsclim_tas_global_30arcmin_daily_1991_2000.nc gswp3-era5_obsclim_tas_dnk_30arcmin_daily_1991_2000.nc

The same command works for the later periods (2001_2010, 2011_2020,
2021_2025), which are not included here.
