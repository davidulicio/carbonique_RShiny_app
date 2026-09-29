# ------------------------------------------------------------------
# CARBONIQUE data explorer: configuration
#
# This file only holds settings. It is read once when the app starts.
# Edit the values below to point the app at another database or level.
# ------------------------------------------------------------------

# Root of the database, organised as <main_dir>/<year>/<site>/<level>/<variable files>
# It can be overridden without editing this file by setting the CARBONIQUE_DB
# environment variable (handy for testing on a laptop or a staging copy).
main_dir <- Sys.getenv("CARBONIQUE_DB", unset = "/home/uqam-site")
#main_dir <- '/Users/saraknox/Code/local_data_cleaning/Projects/uqam-site/Database'
basepath <- main_dir

# Level(s) to read. The first level also provides the time vector (tv_input).
level <- c("Clean/SecondStage")
#level <- c("Clean/ThirdStage", "Met") # NEED TO UPDATE FOR THIRD STAGE WHEN ALL SITES HAVE DATA

tv_input <- "clean_tv" # MAKE SURE tv is in folder

# Only site folders ending in _1 ... _99 are listed (UQAM_0 is excluded)
site_pattern <- "_[1-9][0-9]?$"

# Site shown when the app opens (falls back to the first site if absent)
default_site <- "UQAM_1"

# Units and variable descriptions (AmeriFlux names)
UnitCSVFilePath <- "data/flux_variables.csv"

# Site coordinates used by the radiation diagnostics
coordinatesXLSXFilePath <- "data/site_coordinates_UQAM.xlsx"

# Names of incoming shortwave radiation and incoming PPFD
var_rad <- c("SW_IN_1_1_1", "PPFD_IN_1_1_1")

# Variables compared on the "All sites" page
var_of_interest <- c("datetime",
                     "FC", "FCH4",                          # Ecosystem productivity and C fluxes
                     "VPD", "RH", "TA", "PPFD_IN", "SW_IN", # Meteorological variables
                     "USTAR",                               # Turbulence (proxy for 'good' EC conditions)
                     "LE", "H", "NETRAD", "G")              # Surface energy balance

# How often (minutes) the app re-scans the database folders for new sites/years
refresh_minutes <- 10

# How often (seconds) the app checks whether a site's files were updated
# (it looks at the time vector files only, so this is cheap)
recheck_seconds <- 60

# Cumulative fluxes use gap-filled data, read from this level whatever `level` is
cumulative_level <- "Clean/ThirdStage"
cumulative_pattern <- "^(NEE|FCH4).*_uStar_f$"

# Maximum number of sites kept in memory at once
max_cached_sites <- 8

# Points drawn per series before long periods are simplified for display
# (the highest and lowest value of each time step are kept; zooming in shows
# every half-hour again)
max_points_per_series <- 3000
