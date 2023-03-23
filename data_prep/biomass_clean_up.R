library(DBI)
library(duckdb)
library(dplyr)
library(dbplyr)
library(tidyverse)

dir.create("data_prep/raw_neon",showWarnings = FALSE)
dir.create("assignment/data",showWarnings = FALSE)
Sys.setenv("NEONSTORE_HOME" = normalizePath("data_prep/raw_neon"))

site_list <- c("ABBY", "ORNL", "SERC",
               "TALL", "UNDE", "BART",
               "DEJU", "BLAN","MLBS",
               "OSBS","GRSM")

neonstore::neon_download(product = "DP1.10098.001", site = site_list)


vst_apparentindividual <- neonstore::neon_read(table = "vst_apparentindividual-basic", site = site_list)
map_tag_table <- neonstore::neon_read("vst_mappingandtagging-basic",site = site_list)
vst_perplotperyear <- neonstore::neon_read("vst_perplotperyear-basic",site = site_list)
allometrics <- read_csv("data_prep/Allometrics.csv") |>
  distinct()

neon_domains <- read_csv("data_prep/neon_domains.csv")

map_tag_table <- map_tag_table %>%
  separate(scientificName, sep = " ", into = c("GENUS", "SPECIES", "Other")) |>
  mutate(taxonID = stringr::str_sub(taxonID, 1,4)) |>
  group_by(individualID) |>
  filter(date == max(date)) |>
  ungroup()

#Associate the allometric relationship with the tree species in the mapping and
#tagging table
map_tag_table <- left_join(map_tag_table, allometrics, by = c("GENUS","SPECIES"))

d <- map_tag_table |> select(taxonID, GENUS, SPECIES, B0, B1) |>
  distinct(taxonID, .keep_all = TRUE) |>
  mutate(new_taxonID = ifelse(is.na(B0), "OTHER", taxonID)) |>
  select(-B0,-B1)

map_tag_table_clean <- left_join(map_tag_table, d, by = "taxonID") |>
  mutate(taxonID = new_taxonID) |>
  select(siteID, plotID, individualID, taxonID) |>
  distinct()

allometrics_clean <- left_join(allometrics, d, by = c("GENUS", "SPECIES")) |>
  filter(!is.na(taxonID)) |>
  select(taxonID, B0, B1) |>
  bind_rows(tibble(taxonID = "OTHER", B0 = -2.08, B1 = 2.33)) |>
  distinct()

apparentindividual_clean <- vst_apparentindividual |>
  mutate(year = lubridate::year(date)) |>
  select(year, siteID, individualID, plantStatus, stemDiameter) |>
  distinct()

perplotperyear_clean <- vst_perplotperyear |>
  select(siteID, plotID, plotType, nlcdClass, totalSampledAreaTrees) |>
  distinct(plotID, .keep_all = TRUE)

con <- dbConnect(duckdb(),
                dbdir="assignment/data/neon.duckdb")

dbWriteTable(con, "individual", apparentindividual_clean, overwrite = TRUE)
dbWriteTable(con, "mapping_tagging", map_tag_table_clean, overwrite = TRUE)
dbWriteTable(con, "plot", perplotperyear_clean, overwrite = TRUE)
dbWriteTable(con, "allometrics", allometrics_clean, overwrite = TRUE)
dbWriteTable(con, "domains", neon_domains, overwrite = TRUE)

DBI::dbDisconnect(con)
