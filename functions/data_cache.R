# Fast, cached access to the binary database
# David Trejo Cancino, 2026 (performance rewrite)
#
# Replaces the old daily "load every site" step (scripts/load_save_data.R and
# data/all_data.RData). Each site is now read on demand, which takes well under
# a second, and kept in memory until its files change on disk. Nothing is written
# to the app folder, so the app no longer needs write access there.

.cq_cache <- new.env(parent = emptyenv())

# Files in a level folder that are not data series (same rules as before)
skip_file_regex <- paste(c("\\.txt$", "\\.csv$", "\\.ya?ml$", "\\.mat$", "\\.json$",
                           "clean_tv", "Clean_tv", "DateTime", "TimeVector",
                           "Clean", "clean", "Manual", "NARR", "badWD"), collapse = "|")

# 1. Which sites and years exist --------------------------------------------
# Two-level listing (<year>/<site>) instead of a recursive walk of the whole
# database, which is much faster on large or network drives.
discover_sites <- function(main_dir, level, site_pattern) {
  empty <- data.frame(site = character(), year = character(), stringsAsFactors = FALSE)
  if (!dir.exists(main_dir)) return(empty)
  years <- list.dirs(main_dir, full.names = FALSE, recursive = FALSE)
  years <- sort(years[grepl("^(19|20)\\d{2}$", years)])
  rows <- lapply(years, function(y) {
    s <- list.dirs(file.path(main_dir, y), full.names = FALSE, recursive = FALSE)
    s <- s[grepl(site_pattern, s)]
    if (!length(s)) return(NULL)
    data.frame(site = s, year = y, stringsAsFactors = FALSE)
  })
  db <- do.call(rbind, c(list(empty), rows))
  # keep only site-years that actually contain the first level
  db[dir.exists(file.path(main_dir, db$year, db$site, level[1])), , drop = FALSE]
}

database_index <- function(force = FALSE) {
  stale <- is.null(.cq_cache$index) ||
    difftime(Sys.time(), .cq_cache$index_time, units = "mins") > refresh_minutes
  if (force || stale) {
    .cq_cache$index <- discover_sites(main_dir, level, site_pattern)
    .cq_cache$index_time <- Sys.time()
  }
  .cq_cache$index
}

available_sites <- function() {
  s <- unique(database_index()$site)
  s[order(sub("_\\d+$", "", s), suppressWarnings(as.integer(sub("^.*_", "", s))))]
}

site_years <- function(site) sort(database_index()$year[database_index()$site == site])

# Cheap fingerprint of a site's files: count, total size and newest change time.
# When the cleaning pipeline rewrites a file, the fingerprint changes and the
# site is re-read on the next request.
site_signature <- function(site) {
  yrs <- site_years(site)
  if (!length(yrs)) return(NA_character_)
  paths <- as.vector(outer(file.path(main_dir, yrs, site), level, file.path))
  f <- list.files(paths[dir.exists(paths)], full.names = TRUE)
  if (!length(f)) return("empty")
  info <- file.info(f, extra_cols = FALSE)
  paste(length(f), sum(info$size, na.rm = TRUE),
        format(as.numeric(max(info$mtime, na.rm = TRUE)), nsmall = 0), sep = ":")
}

# 2. Reading one site-year ----------------------------------------------------
# `select` is an optional function(file_names) -> logical, to read only some files.
read_site_year <- function(site, year, select = NULL) {
  base <- file.path(main_dir, year, site)
  tv_path <- file.path(base, level[1], tv_input)
  if (!file.exists(tv_path)) return(NULL)
  tv <- readBin(tv_path, "double", n = file.size(tv_path) %/% 8)
  n <- length(tv)
  # Matlab datenum -> POSIXct (UTC), rounded to the nearest 30 minutes
  secs <- round((tv - 719529) * 86400 / 1800) * 1800
  out <- list(datetime = as.POSIXct(secs, origin = "1970-01-01", tz = "UTC"))
  for (lv in level) {
    p <- file.path(base, lv)
    if (!dir.exists(p)) next
    files <- list.files(p)
    files <- files[!grepl(skip_file_regex, files)]
    files <- files[!dir.exists(file.path(p, files))]
    files <- setdiff(files, names(out))        # first level wins on duplicates
    if (!is.null(select)) files <- files[select(files)]
    for (f in files) {
      x <- readBin(file.path(p, f), "double", n = n, size = 4)
      if (length(x) < n) x <- c(x, rep(NA_real_, n - length(x)))
      out[[f]] <- x
    }
  }
  data.table::setDT(out)
  out
}

# 3. One site, all years (cached) -------------------------------------------
get_site_data <- function(site) {
  if (is.null(site) || !nzchar(site)) return(NULL)
  sig <- site_signature(site)
  if (is.na(sig)) return(NULL)
  key <- paste0("site:", site)
  hit <- .cq_cache[[key]]
  if (!is.null(hit) && identical(hit$signature, sig)) {
    hit$last_used <- Sys.time(); .cq_cache[[key]] <- hit
    return(hit)
  }

  parts <- lapply(site_years(site), function(y) read_site_year(site, y))
  dt <- data.table::rbindlist(parts, use.names = TRUE, fill = TRUE)
  if (!nrow(dt)) return(NULL)
  data.table::setorderv(dt, "datetime")
  dt <- create_EBC_columns(dt)

  vars <- setdiff(names(dt), "datetime")
  vars <- vars[order(tolower(vars))]
  data.table::setcolorder(dt, c("datetime", vars))

  # first/last timestamp with any data (files are padded to full years)
  has_data <- Reduce(`|`, lapply(vars, function(v) !is.na(dt[[v]])), FALSE)
  valid <- which(has_data)
  step <- diff(as.numeric(dt$datetime))

  obj <- list(
    site       = site,
    data       = dt,
    vars       = vars,
    units      = var_units(vars, UnitCSVFilePath),
    years      = sort(unique(as.integer(format(dt$datetime[valid], "%Y")))),
    first      = if (length(valid)) dt$datetime[min(valid)] else NA,
    last       = if (length(valid)) dt$datetime[max(valid)] else NA,
    regular    = length(step) > 0 && all(step == 1800),
    signature  = sig,
    built      = Sys.time(),
    last_used  = Sys.time()
  )
  .cq_cache[[key]] <- obj
  prune_site_cache()
  obj
}

prune_site_cache <- function() {
  keys <- grep("^site:", ls(.cq_cache), value = TRUE)
  if (length(keys) <= max_cached_sites) return(invisible())
  used <- vapply(keys, function(k) as.numeric(.cq_cache[[k]]$last_used), 0)
  rm(list = keys[order(used)][seq_len(length(keys) - max_cached_sites)], envir = .cq_cache)
}

# 4. All sites, a few variables (cached) -------------------------------------
# Same selection rule as before: for each variable of interest, the first file
# whose name without position qualifiers (e.g. TA_1_1_1 -> TA) matches.
select_vars_of_interest <- function(files) {
  short <- gsub("_[[:digit:]]", "", files)
  keep <- logical(length(files))
  for (v in var_of_interest[-1]) {
    i <- which(short == v)[1]
    if (!is.na(i)) keep[i] <- TRUE
  }
  keep
}

get_all_sites_data <- function() {
  sites <- available_sites()
  sig <- paste(sites, vapply(sites, site_signature, ""), collapse = "|")
  hit <- .cq_cache$all_sites
  if (!is.null(hit) && identical(hit$signature, sig)) return(hit)

  parts <- lapply(sites, function(s) {
    yr <- lapply(site_years(s), function(y) read_site_year(s, y, select = select_vars_of_interest))
    d <- data.table::rbindlist(yr, use.names = TRUE, fill = TRUE)
    if (!nrow(d)) return(NULL)
    data.table::setnames(d, gsub("_[[:digit:]]", "", names(d)))
    d <- d[, unique(names(d)), with = FALSE]
    for (v in setdiff(var_of_interest, names(d))) data.table::set(d, j = v, value = NA_real_)
    d <- d[, var_of_interest, with = FALSE]
    data.table::setorderv(d, "datetime")
    d[, site := s]
    d
  })
  data_all <- data.table::rbindlist(parts, use.names = TRUE, fill = TRUE)
  obj <- list(data = data_all,
              units = var_units(var_of_interest, UnitCSVFilePath),
              sites = unique(data_all$site),
              signature = sig)
  .cq_cache$all_sites <- obj
  obj
}

# 5. Site coordinates ------------------------------------------------------
site_coordinates <- function(site) {
  if (is.null(.cq_cache$coords)) {
    .cq_cache$coords <- tryCatch(
      as.data.frame(readxl::read_excel(coordinatesXLSXFilePath, sheet = 1, col_names = TRUE)),
      error = function(e) data.frame(Site = character()))
  }
  co <- .cq_cache$coords
  co <- co[co$Site == site, , drop = FALSE]
  if (!nrow(co)) return(NULL)
  co <- co[1, ]   # some sites have more than one row: use the first
  list(standard_meridian = as.numeric(co$Standard_Meridian),
       lat = as.numeric(co$Latitude), lon = as.numeric(co$Longitude))
}
