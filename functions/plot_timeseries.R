# Time series and all-sites plots (plotly, WebGL)
# 2026 rewrite of the ggplot + ggplotly code that lived in app.R.
# Building plotly traces directly avoids the slow ggplotly conversion and the
# per-point hover text it generated (the old time series sent ~20 MB to the
# browser for one variable).

# Daily means from half-hourly values; a day needs at least `min_frac` of its
# half-hours to get a value. Time stamps mark the end of each half-hour.
daily_mean <- function(datetime, y, min_frac = 0.5) {
  day <- as.Date(datetime - 900, tz = "UTC")
  d <- data.table::data.table(day = day, y = y)
  d[, .(y = if (sum(!is.na(y)) >= 48 * min_frac) mean(y, na.rm = TRUE) else NA_real_), keyby = day]
}

# One half-hourly series. Regular series are sent as a start time + step
# (x0/dx) instead of one time string per point, which halves the payload.
add_halfhourly_trace <- function(fig, datetime, y, name, color, regular, hover_units = "",
                                 size = 3.5, opacity = 0.55) {
  hover <- paste0("%{x|%Y-%m-%d %H:%M}<br>%{y:.4g} ", hover_units, "<extra>", name, "</extra>")
  if (regular && length(y) > 1) {
    add_tr(fig, type = "scattergl", mode = "markers", y = cq_round(y),
           x0 = format(datetime[1], "%Y-%m-%d %H:%M:%S"), dx = 1800 * 1000,
           name = name, marker = list(color = color, size = size, opacity = opacity),
           hovertemplate = hover)
  } else {
    add_tr(fig, type = "scattergl", mode = "markers", y = cq_round(y),
           x = format(datetime, "%Y-%m-%d %H:%M"),
           name = name, marker = list(color = color, size = size, opacity = opacity),
           hovertemplate = hover)
  }
}

add_daily_trace <- function(fig, datetime, y, name, color, hover_units = "") {
  d <- daily_mean(datetime, y)
  add_tr(fig, type = "scatter", mode = "lines", x = format(d$day), y = cq_round(d$y),
         name = name, connectgaps = FALSE,
         line = list(color = color, width = 1.6),
         hovertemplate = paste0("%{x|%Y-%m-%d}<br>%{y:.4g} ", hover_units,
                                "<extra>", name, "</extra>"))
}

# Rows [a, b] of a set of series, trimmed to where at least one has data
trim_to_data <- function(series) {
  has <- Reduce(`|`, lapply(series, function(y) !is.na(y)))
  if (!any(has)) return(NULL)
  c(min(which(has)), max(which(has)))
}

units_of <- function(name, units_tbl) {
  u <- units_tbl$units[match(name, units_tbl$name)]
  if (length(u) == 0 || is.na(u)) "" else u
}

# a) Time series of one variable (all its replicates, e.g. TA_1_1_1 and TA_1_2_1)
plot_timeseries <- function(obj, cols, rows, resolution = "30min", lang = "en") {
  dt <- obj$data
  x <- dt$datetime[rows]
  ys <- lapply(cols, function(cl) dt[[cl]][rows])
  ab <- trim_to_data(ys)
  if (is.null(ab)) return(cq_empty_plot(tr("msg_no_data", lang)))
  idx <- ab[1]:ab[2]
  x <- x[idx]
  units <- units_of(cols[1], obj$units)
  pal <- cq_colors(length(cols))

  fig <- cq_plot()
  for (i in seq_along(cols)) {
    y <- ys[[i]][idx]
    fig <- if (resolution == "daily") {
      add_daily_trace(fig, x, y, cols[i], pal[i], units)
    } else {
      add_halfhourly_trace(fig, x, y, cols[i], pal[i], obj$regular, units)
    }
  }
  cq_layout(fig, xlab = NULL, ylab = unit_label(cols[1], obj$units),
            xaxis = list(type = "date"), showlegend = length(cols) > 1,
            filename = paste(obj$site, cols[1], sep = "_"))
}

# b) All sites: one variable against time or against another variable
plot_all_sites <- function(all, xvar, yvar, sites, resolution = "30min", lang = "en") {
  d <- all$data
  site_levels <- all$sites
  pal <- stats::setNames(cq_colors(length(site_levels)), site_levels)  # colour follows the site
  yunits <- units_of(yvar, all$units)
  fig <- cq_plot()
  for (s in intersect(site_levels, sites)) {
    ds <- d[d$site == s]
    if (xvar == "datetime") {
      ab <- trim_to_data(list(ds[[yvar]]))
      if (is.null(ab)) next
      ds <- ds[ab[1]:ab[2]]
      reg <- nrow(ds) > 1 && all(diff(as.numeric(ds$datetime)) == 1800)
      fig <- if (resolution == "daily") {
        add_daily_trace(fig, ds$datetime, ds[[yvar]], s, pal[[s]], yunits)
      } else {
        add_halfhourly_trace(fig, ds$datetime, ds[[yvar]], s, pal[[s]], reg, yunits,
                             size = 3, opacity = 0.45)
      }
    } else {
      xv <- ds[[xvar]]; yv <- ds[[yvar]]
      if (resolution == "daily") {
        xv <- daily_mean(ds$datetime, xv)$y; yv <- daily_mean(ds$datetime, yv)$y
      }
      ok <- !is.na(xv) & !is.na(yv)
      if (!any(ok)) next
      fig <- add_tr(fig, type = "scattergl", mode = "markers",
                    x = cq_round(xv[ok]), y = cq_round(yv[ok]), name = s,
                    marker = list(color = pal[[s]], size = 3.5, opacity = 0.45),
                    hovertemplate = paste0(xvar, " %{x:.4g}<br>", yvar, " %{y:.4g}<extra>", s, "</extra>"))
    }
  }
  if (!length(fig$data)) return(cq_empty_plot(tr("msg_no_data", lang)))
  cq_layout(fig, xlab = if (xvar == "datetime") NULL else unit_label(xvar, all$units),
            ylab = unit_label(yvar, all$units),
            xaxis = if (xvar == "datetime") list(type = "date") else list(),
            filename = paste("all_sites", yvar, sep = "_"))
}
