# ------------------------------------------------------------------
# Smoke test: run the app's server logic against the real database,
# for every site and every tab, without a browser.
#
# Run from the app folder (the same folder as app.R):
#   Rscript tests/smoke_test.R
# Optional: test another database copy first
#   CARBONIQUE_DB=/path/to/database Rscript tests/smoke_test.R
#
# Prints how long each site takes to read and render, then a summary.
# Exit status is 1 if anything failed, so it can gate a deployment.
# ------------------------------------------------------------------
suppressPackageStartupMessages(library(shiny))
if (!file.exists("app.R")) stop("Run this from the app folder (where app.R is).")

outputs_site <- c("site_stats", "site_meta", "ts_plot", "sc_plot", "sc_fit", "di_plot",
                  "rad_plot", "rad_ccf", "ebc_plot", "ebc_fit", "cum_plot")
failures <- character(0)
timing <- data.frame(site = character(), step = character(), seconds = numeric())

t_start <- Sys.time()
testServer(shinyAppDir("."), {
  sites <- available_sites()
  if (!length(sites)) stop("No sites found under ", main_dir)
  cat(sprintf("Database: %s\nSites: %s\n\n", main_dir, paste(sites, collapse = ", ")))

  for (s in sites) {
    t0 <- Sys.time()
    obj <- get_site_data(s)
    cat(sprintf("%-10s read %d rows x %d variables in %.2f s (last record %s)\n",
                s, nrow(obj$data), length(obj$vars),
                as.numeric(difftime(Sys.time(), t0, units = "secs")), format(obj$last)))
    ch <- site_choices(obj)
    for (lang in c("en", "fr")) {
      t1 <- Sys.time()
      session$setInputs(lang = lang, site = s, nav = "site", site_tab = "rad", period = "all",
                        ts_res = "30min", sc_outliers = TRUE, ebc_outliers = FALSE,
                        ts_var = ch$ts_var$selected, sc_x = ch$sc_x$selected, sc_y = ch$sc_y$selected,
                        di_var = ch$di_var$selected, rad_var = ch$rad_var$selected,
                        rad_year = ch$rad_year$selected, ebc_x = ch$ebc_x$selected,
                        ebc_y = ch$ebc_y$selected, cum_var = ch$cum_var$selected)
      for (o in outputs_site) {
        res <- tryCatch({ force(output[[o]]); "ok" }, error = function(e) conditionMessage(e))
        if (!identical(res, "ok") && nzchar(res)) {
          failures <<- c(failures, sprintf("%s / %s / %s: %s", s, lang, o, res))
        }
      }
      timing[nrow(timing) + 1, ] <<- list(s, paste("all tabs,", lang),
                                          as.numeric(difftime(Sys.time(), t1, units = "secs")))
    }
    # a shorter period and daily means
    session$setInputs(period = "30d", ts_res = "daily")
    for (o in c("ts_plot", "di_plot", "sc_plot")) {
      res <- tryCatch({ force(output[[o]]); "ok" }, error = function(e) conditionMessage(e))
      if (!identical(res, "ok") && nzchar(res)) failures <<- c(failures, sprintf("%s / 30 days / %s: %s", s, o, res))
    }
  }

  # All sites page
  for (res_ in c("daily", "30min")) {
    t1 <- Sys.time()
    session$setInputs(nav = "all", xcol_all = "datetime", ycol_all = "TA", all_res = res_, all_sites = sites)
    res <- tryCatch({ force(output$all_plot); "ok" }, error = function(e) conditionMessage(e))
    timing[nrow(timing) + 1, ] <<- list("all sites", paste("all_plot", res_), as.numeric(difftime(Sys.time(), t1, units = "secs")))
    if (!identical(res, "ok") && nzchar(res)) failures <<- c(failures, sprintf("all sites / %s: %s", res_, res))
  }
  session$setInputs(xcol_all = "NETRAD", ycol_all = "LE", all_res = "30min")
  res <- tryCatch({ force(output$all_plot); "ok" }, error = function(e) conditionMessage(e))
  if (!identical(res, "ok") && nzchar(res)) failures <<- c(failures, sprintf("all sites LE vs NETRAD: %s", res))
})

cat("\nRender time (server side, all outputs of each step):\n")
print(timing, row.names = FALSE, digits = 2)
cat(sprintf("\nTotal time: %.1f s\n", as.numeric(difftime(Sys.time(), t_start, units = "secs"))))
if (length(failures)) {
  cat("\nFAILED:\n", paste0("  ", failures, collapse = "\n"), "\n", sep = "")
  quit(status = 1)
} else {
  cat("\nAll outputs rendered without errors.\n")
}
