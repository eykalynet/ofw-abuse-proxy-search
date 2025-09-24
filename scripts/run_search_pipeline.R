# =============================================================================
# POLO Domestic Abuse Project — Web SERP + Google Trends Collector
# Author: Erika Lynet Salvador
# File: 01_collect_serp_trends.R
# -----------------------------------------------------------------------------
# This script is designed to collect two kinds of information that help us
# understand how issues around migrant domestic worker abuse are represented
# online. First, we will download search results from Google using SerpAPI,
# which gives us the titles, snippets, and links that ordinary users would see.
# Second, we will gather Google Trends data, which provides an index of how
# often certain terms are searched over time in different countries.
#
# To run this file successfully, you will need:
#   • R and the packages listed below
#   • A SerpAPI key saved in your ~/.Renviron file
#
# The script will automatically create the necessary folders (`data/raw`,
# `data/processed`, and `config`) and will save CSV outputs in those folders.
# =============================================================================


# =========================== 1) Package Setup =================================
# We begin by making sure that all of the R packages needed for the script are
# available. If any of them are missing, the script installs them. Once they
# are present, we load them quietly so that messages do not clutter the output.
# Packages like `httr2` and `jsonlite` are used for web requests and parsing,
# while `dplyr`, `purrr`, `tidyr`, and `stringr` are for data wrangling. 
# `yaml` allows us to read settings from a configuration file, and `gtrendsR`
# connects to Google Trends.

required_pkgs <- c(
  "httr2","jsonlite","dplyr","purrr","stringr",
  "readr","tibble","tidyr","yaml","gtrendsR"
)

to_install <- setdiff(required_pkgs, rownames(installed.packages()))
if (length(to_install)) install.packages(to_install, quiet = TRUE)

suppressPackageStartupMessages({
  library(httr2)
  library(jsonlite)
  library(dplyr)
  library(purrr)
  library(stringr)
  library(readr)
  library(tibble)
  library(tidyr)
  library(yaml)
  library(gtrendsR)
})

# As a convenience, we define a small helper operator `%||%`. It says: “if the
# first value is missing or blank, use the second value instead.” This is
# useful when we want to provide defaults in case a config setting is not found.
`%||%` <- function(a,b) if (is.null(a) || (is.character(a) && !nzchar(a))) b else a


# =========================== 2) Paths & Folders ===============================
# Next, we make sure that the script has a consistent sense of where to save
# and read files. We define a function `here()` that always builds a path
# starting from the current project root. After that, we create the folders
# `data/raw`, `data/processed`, and `config` if they do not already exist.
# This means anyone who runs the script will automatically have the right
# folder structure without needing to set it up manually.

here <- function(...) normalizePath(file.path(getwd(), ...), winslash = "/", 
                                    mustWork = FALSE)

dir.create(here("data"), showWarnings = FALSE)
dir.create(here("data","raw"), showWarnings = FALSE, recursive = TRUE)
dir.create(here("data","processed"), showWarnings = FALSE, recursive = TRUE)
dir.create(here("config"), showWarnings = FALSE, recursive = TRUE)


# =========================== 3) Configuration =================================
# After setting up the folders, we decide what searches to run and what time
# period to look at. By default, the script comes with a list of English and
# Tagalog queries related to domestic worker abuse, along with some example
# countries (Saudi Arabia, Hong Kong, UAE, Italy) and languages. 
#
# For time windows, we  default to "as early as possible":
#   • For Google SERP (via SerpAPI): we leave `tbs = NULL` so Google returns
#     all available results without a date filter.
#   • For Google Trends: we set `trends_time = "all"`, which is the maximum
#     range available. 

default_cfg <- list(
  queries = c(
    "domestic worker abuse",
    "OFW contract violation",
    "household service worker passport withheld",
    "pang-aabuso kasambahay",
    "paglabag sa kontrata OFW",
    "kinuha ang pasaporte kasambahay"
  ),
  destinations = c("SA","HK","AE","IT"),
  languages    = c("lang_en","lang_tl"),
  tbs = NULL,          # no date restriction → all available SERP results
  pages = 10,
  pause = c(0.8, 1.6),
  trends_time = "all"  # Google Trends earliest (2004) → present
)

cfg_path <- here("config","queries.yml")
cfg <- if (file.exists(cfg_path)) {
  message("Reading config from config/queries.yml")
  read_yaml(cfg_path)
} else {
  message("No config/queries.yml found — using defaults.")
  default_cfg
}

cfg$queries      <- as.character(cfg$queries %||% default_cfg$queries)
cfg$destinations <- as.character(cfg$destinations %||% default_cfg$destinations)
cfg$languages    <- as.character(cfg$languages %||% default_cfg$languages)
cfg$tbs          <- if (!is.null(cfg$tbs)) as.character(cfg$tbs) else NULL
cfg$pages        <- as.integer(cfg$pages %||% default_cfg$pages)
cfg$pause        <- as.numeric(cfg$pause %||% default_cfg$pause)
cfg$trends_time  <- as.character(cfg$trends_time %||% default_cfg$trends_time)
