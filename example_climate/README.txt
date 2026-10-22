The following commands were used to create the files in this container:

cdo -f nc4c -z zip_5 -L -ifthen -selname,m_DNK countrymasks-binary_30arcmin.nc gswp3-era5_obsclim_tas_global_30arcmin_daily_1991_2000.nc gswp3-era5_obsclim_tas_dnk_30arcmin_daily_1991_2000.nc
cdo -f nc4c -z zip_5 -L -ifthen -selname,m_DNK countrymasks-binary_30arcmin.nc gswp3-era5_obsclim_tas_global_30arcmin_daily_2001_2010.nc gswp3-era5_obsclim_tas_dnk_30arcmin_daily_2001_2010.nc
cdo -f nc4c -z zip_5 -L -ifthen -selname,m_DNK countrymasks-binary_30arcmin.nc gswp3-era5_obsclim_tas_global_30arcmin_daily_2011_2020.nc gswp3-era5_obsclim_tas_dnk_30arcmin_daily_2011_2020.nc
cdo -f nc4c -z zip_5 -L -ifthen -selname,m_DNK countrymasks-binary_30arcmin.nc gswp3-era5_obsclim_tas_global_30arcmin_daily_2021_2025.nc gswp3-era5_obsclim_tas_dnk_30arcmin_daily_2021_2025.nc
