# Copied from ISIMIPglobalLER (github: isimipgloballer, commit a8d9608),
# author Johannes Feldbauer, GPL (>= 3). Unchanged.

#' Calculate cloud cover and dew point temperature
#'
#' @param date A POSIxct vector with the dates of the meteorological data
#' @param airt A double precision vector with the air temperature in °C
#' @param relh A double precision vector with the relative humidity in %
#' @param swr A double precision vector with the short wave radiation in W/m²
#' @param lat The latitude of the location
#' @param lon The longitude of the location
#' @param elev Elevation of the location
#'
#' @returns A `list` with the calculated cloud cover `ccsim` and dew point temperature `dewt_daily`
#' @export
calc_cc_dewp <- function(date, airt, relh, swr, lat, lon, elev) {


  # ── Date handling ──────────────────────────────────────────────────────────

  date <- seq(
    from = date[1],
    to   = date[length(date)] + 86400 - 3600,  # +1 day -1 hour (in seconds)
    by   = "hour"
  )

  yday <- yday(date)          # Day of year
  hour <- hour(date)          # Hour of day (0–23)
  hour[hour == 0] <- 24       # Replace midnight hour 0 with 24

  # ── Standard meridian ─────────────────────────────────────────────────────
  stdmer <- seq(-180, 165, by = 15)                         # -180, -165, ..., 165
  Lsm    <- stdmer[which.min(abs(lon - stdmer))]            # Local standard meridian (degrees)

  # ── Solar geometry constants ───────────────────────────────────────────────
  Hsc <- 1390    # Solar constant (W/m2)
  cd  <- 0.06    # Dust coefficient
  Rg  <- 0.045   # Reflectivity of the ground - extended mixed forest

  theta <- lat * pi / 180                                        # Latitude in radians
  r     <- 1 + 0.017 * cos((2 * pi / 365) * (186 - yday))       # Relative earth-sun distance
  d     <- 23.45 * pi / 180 * cos((2 * pi / 365) * (172 - yday))# Declination of the sun
  dts   <- (1 / 15) * (Lsm - lon)                               # Fraction of 15-deg increment Lsm is east of lon

  # Solar angle value – clamped to [-1, 1]
  value <- (sin(theta) * sin(d)) / (cos(theta) * cos(d))
  value[value >  1] <-  1
  value[value < -1] <- -1

  tss <- (12 / pi) * acos(-value) + dts + 12   # Time of sunset
  tsu <- -tss + (2 * dts) + 24                 # Time of sunrise

  # Correction factor: 1 when sun is above horizon, else 0
  gamma        <- rep(0, length(tss))
  gamma[hour > tsu & hour < tss] <- 1

  # ── Hb and He calculations ─────────────────────────────────────────────────
  dum1 <- which(hour <= 12)
  dum2 <- which(hour >  12)

  hb1        <- pi / 12 * (hour - 1 - dts)
  hb1[dum1]  <- hb1[dum1] + pi
  hb1[dum2]  <- hb1[dum2] - pi
  hb         <- hb1
  hb[hb1 >  2 * pi] <- hb[hb1 >  2 * pi] - 2 * pi
  hb[hb1 <  0]      <- hb[hb1 <  0]      + 2 * pi

  he1        <- pi / 12 * (hour - dts)
  he1[dum1]  <- he1[dum1] + pi
  he1[dum2]  <- he1[dum2] - pi
  he         <- he1
  he[he1 >  2 * pi] <- he[he1 >  2 * pi] - 2 * pi
  he[he1 <  0]      <- he[he1 <  0]      + 2 * pi

  # ── Extraterrestrial horizontal radiation ─────────────────────────────────
  Ho <- Hsc / (r^2) * (
    sin(theta) * sin(d) +
      (12 / pi) * cos(theta) * cos(d) * (sin(he) - sin(hb))
  ) * gamma

  # ── Radiation scattering and absorption ───────────────────────────────────
  w       <- (he + hb) / 2                                    # Hour angle
  alpha1  <- abs(sin(theta) * sin(d) + cos(theta) * cos(d) * cos(w))
  alpha   <- atan(alpha1 / sqrt(1 - alpha1^2))                # Solar altitude

  theta_am1 <- ((288 - 0.0065 * elev) / 288)^5.256
  theta_am2 <- sin(alpha) + 0.15 * ((alpha * 180 / pi) + 3.855)^(-1.253)
  theta_am  <- theta_am1 / theta_am2                          # Optical air mass

  # ── Dewpoint temperature ───────────────────────────────────────────────────
  dewt_daily  <- 243.04 * (
    log(relh / 100) + ((17.625 * airt) / (243.04 + airt))
  ) / (
    17.625 - log(relh / 100) - ((17.625 * airt) / (243.04 + airt))
  )
  dewt_hourly <- rep(dewt_daily, each = 24)                   # Expand daily → hourly

  Pwc <- 0.85 * exp(0.11 + 0.0614 * dewt_hourly)             # Precipitable atmospheric water content

  # Atmospheric transmission coefficients after scattering and absorption
  a2 <- exp(-(0.465 + 0.134 * Pwc) * (0.179 + 0.421 * exp(-0.721 * theta_am)) * theta_am)
  a1 <- exp(-(0.465 + 0.134 * Pwc) * (0.129 + 0.171 * exp(-0.88  * theta_am)) * theta_am)
  at <- (a2 + 0.5 * (1 - a1 - cd)) / (1 - 0.5 * Rg * (1 - a1 - cd))  # Attenuation

  Ho          <- at * Ho
  Ho[Ho < 0]  <- 1                                            # Replace negative values

  # ── Daily averaging ────────────────────────────────────────────────────────
  # Reshape Ho into a matrix with 24 rows (one per hour) and colMeans over days
  Ho_daily <- colMeans(matrix(Ho, nrow = 24))

  # ── Cloud cover simulation ─────────────────────────────────────────────────
  ccsim <- rep(NA, length(Ho_daily))

  for (i in seq_along(Ho_daily)) {
    if (!is.na(Ho_daily[i]) && Ho_daily[i] > swr[i]) {
      ccsim[i] <- sqrt((1 - (swr[i] / Ho_daily[i])) / 0.65)
    }
  }

  ccsim[ccsim > 1] <- 1

  # This happens usually in winter at high latitudes – put a mean value of 0.5
  if (is.na(ccsim[1]))                  ccsim[1]             <- 0.5
  if (is.na(ccsim[length(ccsim)]))      ccsim[length(ccsim)] <- 0.5

  # Interpolate remaining NAs linearly
  ccsim <- na.approx(ccsim, na.rm = FALSE)

  ccsim[ccsim > 1] <- 1

  # ── Return ─────────────────────────────────────────────────────────────────
  return(list(ccsim = ccsim, dewt_daily = dewt_daily))
}
