# Cumulative fluxes for complete years of gap-filled (ThirdStage) data
# 2026: moved out of app.R and ported to data.table + plotly (same method).

plot_cumulative <- function(obj, cumcol, lang = "en") {
  if (!any(grepl("ThirdStage", level))) {
    return(cq_empty_plot(tr("msg_no_third", lang, level = paste(level, collapse = ", "))))
  }
  if (is.null(cumcol) || !nzchar(cumcol) || !(cumcol %in% names(obj$data))) {
    return(cq_empty_plot(tr("msg_no_data", lang)))
  }
  # Conversion factors: umol CO2 m-2 s-1 -> gC m-2 d-1 ; nmol CH4 m-2 s-1 -> gC m-2 d-1
  conv <- list(CO2 = 12.01 / (10^6) * (60 * 60 * 24), CH4 = 12.01 / (10^9) * (60 * 60 * 24))
  cf <- if (grepl("^FCH4", cumcol)) conv$CH4 else conv$CO2

  lt <- as.POSIXlt(obj$data$datetime)
  df <- data.table::data.table(year = lt$year + 1900L, DOY = lt$yday + 1L, var = obj$data[[cumcol]])

  # Full years only (>= 365 days of half-hours)
  count_yr <- df[, .(count = sum(!is.na(var))), by = year]
  yrs <- count_yr$year[count_yr$count >= 17520]
  if (!length(yrs)) return(cq_empty_plot(tr("msg_no_full_year", lang)))
  df <- df[year >= min(yrs) & year <= max(yrs)]
  daily <- df[, .(var = mean(var) * cf), keyby = .(year, DOY)]
  daily[, var_cum := cumsum(var), by = year]

  pal <- stats::setNames(cq_colors(length(unique(daily$year))), unique(daily$year))
  fig <- cq_plot()
  for (yy in unique(daily$year)) {
    d <- daily[year == yy]
    fig <- add_tr(fig, type = "scatter", mode = "lines", x = d$DOY, y = signif(d$var_cum, 4),
                           name = as.character(yy), line = list(color = pal[[as.character(yy)]], width = 2),
                           hovertemplate = paste0(yy, " \u00b7 ", tr("ax_doy", lang), " %{x}<br>%{y:.1f} gC m-2<extra></extra>"))
  }
  fig$layout <- list(shapes = list(list(type = "line", xref = "paper", x0 = 0, x1 = 1, y0 = 0, y1 = 0,
                                            line = list(color = cq_brand$muted, dash = "dot", width = 1))))
  cq_layout(fig, xlab = tr("ax_doy", lang), ylab = paste0(cumcol, " (gC m-2)"),
            filename = paste0("cumulative_", cumcol))
}
