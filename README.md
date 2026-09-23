# CARBONIQUE data explorer

R Shiny app to explore the half-hourly data collected at the CARBONIQUE flux sites
(time series, scatter plots, diurnal cycles, radiation diagnostics, energy balance
closure, cumulative fluxes, and a comparison of all sites). The interface is in
French and English.

More details on the project: https://carbonique.ca/

## Folder layout

| Path | What it is |
|---|---|
| `app.R` | Interface and server logic |
| `scripts/UQAM_ini.R` | Settings: database path, data level, default site, variables |
| `functions/` | Data access (`data_cache.R`), analyses and plots, translations (`i18n.R`), look and feel (`cq_theme.R`) |
| `www/` | CARBONIQUE logos, Roboto font files, `carbonique.css`, `carbonique.js` |
| `data/flux_variables.csv` | Units and descriptions (AmeriFlux names) |
| `data/site_coordinates_UQAM.xlsx` | Site coordinates for the radiation diagnostics |
| `tests/smoke_test.R` | Renders every tab for every site against the database, no browser needed |
| `DEPLOY.md` | How to install this version on the Shiny server |

## Run it on your own computer

You need R (4.1 or newer) and access to a copy of the database.

```r
install.packages(c("shiny", "bslib", "plotly", "data.table", "readxl", "jsonlite"))
Sys.setenv(CARBONIQUE_DB = "W:/Database")   # folder with <year>/<site>/Clean/SecondStage
shiny::runApp(".")
```

## Check it before deploying

From the app folder:

```sh
Rscript tests/smoke_test.R
```

It reads every site, renders every plot in both languages and ends with
"All outputs rendered without errors." (exit status 1 otherwise).

## How the data are read

The app reads the binary database directly (`<year>/<site>/<level>/<variable>`, float32
series plus the `clean_tv` time vector). Each site is read when it is first opened
(well under a second) and kept in memory. When the cleaning pipeline updates the
files, the change is detected and the site is read again on the next request, so no
daily rebuild or saved `.RData` file is needed.

## Credits

Developed by Sara Knox (2024) from the AmeriFlux data visualization app by Sophie
Ruehr. Server setup by Tim Elrick. Performance update, CARBONIQUE visual identity and
French interface by David Trejo Cancino (2026).
