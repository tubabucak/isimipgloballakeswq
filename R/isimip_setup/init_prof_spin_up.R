# Copied from ISIMIPglobalLER (github: isimipgloballer, commit a8d9608),
# author Johannes Feldbauer, GPL (>= 3). Unchanged apart from comments.

#' Initial temperature profile from latitude
#'
#' @returns data.frame with `Depth_meter` and `Water_Temperature_celsius`
create_init_prof <- function(max_depth, lat) {

  temp <- case_when(abs(lat) > 80 ~ 2,
                    abs(lat) <= 80 & abs(lat) > 60 ~ 4,
                    abs(lat) <= 60 & abs(lat) > 40 ~ 6,
                    abs(lat) <= 40 & abs(lat) > 20 ~ 10,
                    abs(lat) <= 20 & abs(lat) > 15 ~ 15,
                    abs(lat) <= 15 ~ 20)

  dep <- seq(from = 0, to = max_depth - 0.1, length.out = 5)

  data.frame(Depth_meter = dep,
             Water_Temperature_celsius = temp)
}

#' Add a spin-up period by repeating the first years of meteo.csv
#'
#' Prepends `spin_up_years` copies of the first years to meteo.csv and moves
#' the start date in LakeEnsemblR.yaml back by `spin_up_years`.
add_spin_up <- function(folder, spin_up_years = 1) {

  the_start_date <- get_yaml_multiple(file.path(folder, "LakeEnsemblR.yaml"),
                                      key1 = "time", key2 = "start") |>
    as.POSIXct(format = "%Y-%m-%d %H:%M:%S", tz = "UTC")

  ### Meteo file
  df_meteo <- read_csv(file.path(folder, "meteo.csv"), show_col_types = FALSE)
  df_meteo <- mutate(df_meteo, datetime = as.POSIXct(datetime, tz = "UTC"))

  # data to be added
  df_meteo_add <- filter(df_meteo,
                         datetime < (the_start_date + years(spin_up_years))) |>
    mutate(datetime_add = datetime - years(spin_up_years)) |>
    filter(!is.na(datetime_add)) |>
    select(-datetime) |>
    rename(datetime = "datetime_add") |>
    relocate(datetime, .before = 1)

  # check if new data is leap year
  if(any(leap_year(year(df_meteo_add$datetime)))) {
    years_add <- df_meteo_add |>
      mutate(year = year(datetime)) |>
      group_by(year) |>
      reframe(leap = any(leap_year(datetime)),
              nday = n()) |>
      filter(leap & nday != 366)

    days_add <- df_meteo_add |>
      filter(year(datetime) %in% years_add$year &
               month(datetime) == 2 &
               day(datetime) == 28) |>
      mutate(datetime = datetime + days(1))

    df_meteo_add <- df_meteo_add |>
      add_row(days_add) |> arrange(datetime)
  }

  df_meteo <- df_meteo_add |> add_row(df_meteo)

  new_start_date <- format(the_start_date - years(spin_up_years), "%Y-%m-%d %H:%M:%S")

  # change configuration file
  input_yaml_multiple(file.path(folder, "LakeEnsemblR.yaml"),
                      key1 = "time", key2 = "start",
                      value = new_start_date,
                      verbose = FALSE)

  # write meteo file
  write.csv(df_meteo, file.path(folder, "meteo.csv"), quote = FALSE,
            row.names = FALSE)
}
