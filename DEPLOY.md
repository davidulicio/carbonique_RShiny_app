# Deploying the 2026 version of the CARBONIQUE data explorer

This version is a drop-in replacement for the current app at
`https://288-gic-rshiny.geog.mcgill.ca/knox/carbonique/`. Same data, same database
path (`/home/uqam-site`), same analyses; it is faster, follows the CARBONIQUE visual
identity and has a French/English switch.

## 1. Check the R packages on the server

```r
for (p in c("shiny", "bslib", "plotly", "htmlwidgets", "data.table", "readxl", "jsonlite"))
  cat(p, format(packageVersion(p)), "\n")
```

Minimum versions: shiny 1.6, bslib 0.5, plotly 4.10, htmlwidgets 1.5.3, data.table 1.12.
Tested with R 4.3.3, shiny 1.8.0, bslib 0.6.1, plotly 4.10.4, data.table 1.14.10.

No new packages are needed. The app no longer uses tidyverse, shinydashboard,
shinycssloaders, gridExtra, ggrepel, hms, readr, lubridate or forecast (they can stay
installed).

## 2. Install it next to the current app first

Copy the folder to a new app directory so both versions run side by side, for example
(user directory layout):

```sh
cp -r carbonique_RShiny_app ~/ShinyApps/carbonique-beta
```

It is then available at `.../knox/carbonique-beta/`. Nothing in the current app changes.

## 3. Test it on the server, with the real database

```sh
cd ~/ShinyApps/carbonique-beta
Rscript tests/smoke_test.R
```

This reads every site and renders every tab in English and French. It must end with
`All outputs rendered without errors.` Then open the beta URL and click through the tabs.

## 4. Switch

When the beta looks right, replace the current app folder with this one (or point the
current folder at this branch with `git checkout redesign-2026`). To roll back, put the
previous folder back or `git checkout main`.

## What changed for the server

* **No daily rebuild.** The old app re-read every site on the first visit of each day and
  saved `data/all_data.RData` and `data/updated.txt`. The new app reads each site on
  demand (well under a second) and keeps it in memory until the files change. It writes
  nothing to its folder, so it no longer needs write access there. The two old files and
  `scripts/load_save_data.R` were removed.
* **Faster plots.** Plots are built directly with plotly (WebGL) instead of converting
  ggplot objects with `ggplotly()`, and values are rounded to 5 significant digits
  before being sent. The time series of one variable went from about 20 MB to under
  1.5 MB, and from about 4 s to 0.15 s of server time. Rendered plots are cached
  (`bindCache`), so the next visitor asking for the same view gets it immediately.
* **No external downloads.** The Roboto font and the logos are served from `www/`.
* **Optional, recommended:** keep the R process alive between visits so the in-memory
  cache survives. In `/etc/shiny-server/shiny-server.conf`, inside the relevant
  `location` block:

  ```
  app_idle_timeout 1800;
  ```

## Things to review (analysis changes)

These are corrections of issues found while testing. Please check that they match the
intent:

1. **Regression direction** (scatter and energy balance tabs). The line drawn is Y on X,
   but the old title reported the slope of X on Y. Title, line and per-year chart now
   all use `lm(y ~ x)`.
2. **Negative values were dropped** from scatter plots and fits because both axes were
   forced to start at 0. Night-time H, LE and NETRAD are now included.
3. **Year effect** is tested with `year` as a factor (one line per year), which matches
   the per-year lines that are drawn.
4. **Cross-correlation plot** (radiation tab) never displayed on the server: it called
   `forecast::ggCcf()` but the forecast package was not loaded. It now uses base R `ccf()`.
5. **Radiation "exceeds" points** are now measured > potential (strictly), so night-time
   zeros are not flagged. Window lags use paired finite values.
6. **H_LE** uses the first H and the first LE column found (the old code summed every
   match, which could double count if both `H` and `H_*_uStar_orig` exist).
7. **Time series variable groups**: choosing `TA` shows `TA_1_1_1`, `TA_1_2_1`...;
   `TA_F` is its own entry (before, `TA` also pulled in the `TA_F_*` series).
8. **One period selector** in the sidebar now applies to the time series, scatter,
   diurnal and energy balance tabs. The old app had two date sliders with the same id
   (only one worked) and the time series ignored it.

The site data, potential radiation and 15-day composites were checked against the old
functions on the same database copy: identical values.

## Configuration

Everything is in `scripts/UQAM_ini.R`: `main_dir` (or the `CARBONIQUE_DB` environment
variable), `level` (switch to ThirdStage there to enable cumulative fluxes),
`default_site`, the radiation variable names and the variables of the All sites page.

The radiation diagnostics need each site's coordinates in
`data/site_coordinates_UQAM.xlsx` (columns Site, Standard_Meridian, Latitude,
Longitude). UQAM_3, UQAM_4, UQAM_5 and MCGILL_1 are not in that file yet; the tab shows
a message for them until rows are added.
