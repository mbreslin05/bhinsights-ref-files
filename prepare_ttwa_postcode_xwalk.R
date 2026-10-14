# ==============================================================================
# Client:  Beauhurst Insights (internal)
# Title:   One-off: ONS postcode -> TTWA crosswalk as a gzipped CSV for git
# Author:  MB
# Date:    2026-10-14
# ==============================================================================

"
Run this ONCE per ONS release, by hand.

It produces `ttwa_postcode_xwalk.csv.gz`: every postcode in the ONSPD, live
and terminated, with its 2011 TTWA code and name. Three columns -- `pcds`,
`ttwa`, `ttwa_nm` -- one row per postcode.

WHY GZIPPED CSV. Uncompressed it is ~77MB, which GitHub will not take. Gzip
gets it to ~8MB and it is still a plain CSV underneath: read_csv(),
fread(), pandas and `zcat` all open the .gz directly, no unpacking step.
Parquet would be smaller again but is not human-readable, and being the
readable copy is this file's whole job. (The build in insights-master-data
reads its own parquet via prepare_ttwa_xwalk.R; this is not that.)

FIXED: the first version of this file was assembled in Excel. Excel silently
cut it at 1,048,575 data rows -- its sheet limit -- so it stopped at HP2 7RT
and was missing 61% of postcodes, including most of London. It also carried
the literal string '#N/A' as the name of every postcode with no TTWA, which
was a lookup miss, not data. It is built here instead, with a row-count
floor so a truncated input cannot pass quietly again.
"


# ==============================================================================
# 1. SETUP
# ==============================================================================

library(tidyverse)

PROJECT_DIR <- '~/Repos/bhinsights-ref-files'
setwd(PROJECT_DIR)

"
Both inputs are ONS public reference data, held outside this repo -- the
same two files prepare_ttwa_xwalk.R reads.

`ONSPD_IN` is the two-column (`pcds`, `ttwa`) extract of the May 2025 ONSPD.
`TTWA_NAMES_IN` is ONS's 'Travel to Work Areas (December 2011) Names and Codes
in the United Kingdom', which ships with the boundary files rather than in the
ONSPD zip.
"


ONSPD_IN <- '~/Repos/insights-master-data/ONSPD_MAY_2025_UK_pcds_ttwa.csv'

TTWA_NAMES_DIR  <- '~/Documents/Projects/TTWA jitter/data'
TTWA_NAMES_FILE <- paste0('Travel_to_Work_Areas_(December_2011)_Names_and_',
                          'Codes_in_the_United_Kingdom.csv')

TTWA_NAMES_IN <- file.path(TTWA_NAMES_DIR, TTWA_NAMES_FILE)

OUT_CSV_GZ <- 'ttwa_postcode_xwalk.csv.gz'

MIN_POSTCODES <- 2500000L   # a full UK ONSPD is ~2.7m; fewer is a partial file


# ==============================================================================
# 2. THE CROSSWALK
# ==============================================================================

"
`pcds` is kept exactly as ONS write it ('AB1 0AA'), not squashed to the
pc_key() form the build uses. This is the copy people look things up in by
eye, so it should match how a postcode is actually written.

Everything is read as character, so no code is ever guessed into a number.
"


if (!file.exists(ONSPD_IN)) {
  stop('ONSPD input not found at ', ONSPD_IN, '.')
}

pcd_ttwa <- read_csv(ONSPD_IN,
                     col_types = cols(.default = col_character()),
                     progress  = FALSE) %>%
  select(pcds, ttwa) %>%
  mutate(pcds = str_squish(pcds),
         ttwa = str_squish(ttwa)) %>%
  filter(!is.na(pcds), pcds != '')

if (nrow(pcd_ttwa) < MIN_POSTCODES) {
  stop('Only ', format(nrow(pcd_ttwa), big.mark = ','), ' postcodes in ',
       ONSPD_IN, '; a full UK ONSPD has ~2.7m. If it is exactly 1,048,575, ',
       'it has been through Excel and been truncated.')
}

if (any(duplicated(pcd_ttwa$pcds))) {
  stop('pcd_ttwa is not unique on pcds: ', sum(duplicated(pcd_ttwa$pcds)),
       ' duplicates. Suspect a doubled or overlapping extract.')
}

message(format(nrow(pcd_ttwa), big.mark = ','), ' postcodes, ',
        n_distinct(pcd_ttwa$ttwa), ' distinct TTWA values')


# ==============================================================================
# 3. THE NAMES
# ==============================================================================

"
Columns are matched on pattern (TTWA11CD / TTWA11NM) rather than exact name,
so a 2021-based release should not need this edited.

Postcodes with a blank TTWA, and the Channel Islands (L99999999) and Isle of
Man (M99999999) pseudo-codes, have no ONS name. They are KEPT, with a blank
name, rather than dropped: someone looking up a Jersey postcode should find
it and see it has no TTWA, not wonder whether it was missed. processing.R
drops them at build time, which is the right place for that call.
"


ttwa_names <- read_csv(TTWA_NAMES_IN,
                       col_types = cols(.default = col_character()),
                       progress  = FALSE)

code_col <- str_subset(names(ttwa_names), '^TTWA\\d*CD$')
name_col <- str_subset(names(ttwa_names), '^TTWA\\d*NM$')

if (length(code_col) != 1 || length(name_col) != 1) {
  stop('Could not identify the code and name columns in ', TTWA_NAMES_IN,
       '. Found: ', paste(names(ttwa_names), collapse = ', '))
}

ttwa_names <- ttwa_names %>%
  select(ttwa = all_of(code_col), ttwa_nm = all_of(name_col)) %>%
  mutate(across(everything(), str_squish)) %>%
  filter(!is.na(ttwa), ttwa != '') %>%
  distinct()

# one name per code, or the join below fans out
if (any(duplicated(ttwa_names$ttwa))) {
  stop('TTWA names file has more than one name for some codes.')
}

unnamed <- pcd_ttwa %>%
  filter(!is.na(ttwa), !str_detect(ttwa, '9{6}$')) %>%
  distinct(ttwa) %>%
  anti_join(ttwa_names, by = 'ttwa') %>%
  pull(ttwa)

if (length(unnamed) > 0) {
  stop(length(unnamed), ' TTWA codes on postcodes have no name (',
       paste(head(unnamed, 5), collapse = ', '), '). The names file and the ',
       'postcode file are from different editions.')
}


# ==============================================================================
# 4. WRITE
# ==============================================================================

xwalk <- pcd_ttwa %>%
  left_join(ttwa_names, by = 'ttwa') %>%
  arrange(pcds)

# na = '' so a missing TTWA is a blank cell, not the string 'NA'
write_csv(xwalk, OUT_CSV_GZ, na = '')

"
Read it back and check it round-trips, since the point of this file is that
it is complete.
"


xwalk_check <- read_csv(OUT_CSV_GZ,
                        col_types = cols(.default = col_character()),
                        progress  = FALSE)

if (!identical(nrow(xwalk_check), nrow(xwalk))) {
  stop('Wrote ', nrow(xwalk), ' rows but read back ', nrow(xwalk_check), '.')
}

message('Wrote ', OUT_CSV_GZ, ': ', format(nrow(xwalk), big.mark = ','),
        ' postcodes, ', format(file.size(OUT_CSV_GZ) / 1024^2, digits = 3),
        ' MB')
