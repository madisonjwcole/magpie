# |  (C) 2008-2021 Potsdam Institute for Climate Impact Research (PIK)
# |  authors, and contributors see CITATION.cff file. This file is part
# |  of MAgPIE and licensed under AGPL-3.0-or-later. Under Section 7 of
# |  AGPL-3.0, you are granted additional permissions described in the
# |  MAgPIE License Exception, version 1.0 (see LICENSE file).
# |  Contact: magpie@pik-potsdam.de

# --------------------------------------------------------------
# description: Interpolates land pools to 0.5 degree resolution
# comparison script: FALSE
# ---------------------------------------------------------------

library(lucode2)
library(magpie4)
library(luscale)
library(madrat)

############################# BASIC CONFIGURATION ##############################
if(!exists("source_include")) {
  outputdir <- "output/LAMA65_Sustainability/"
  readArgs("outputdir")
}
map_file                   <- Sys.glob(file.path(outputdir, "clustermap_*.rds"))
gdx                        <- file.path(outputdir,"fulldata.gdx")
land_hr_file               <- file.path(outputdir,"avl_land_full_t_0.5.mz")
urban_land_hr_file         <- file.path(outputdir,"f34_urbanland_0.5.mz")
land_hr_out_file           <- file.path(outputdir,"cell.land_0.5.mz")
land_hr_share_out_file     <- file.path(outputdir,"cell.land_0.5_share.mz")
croparea_hr_share_out_file <- file.path(outputdir,"cell.croparea_0.5_share.mz")
land_hr_split_file         <- file.path(outputdir,"cell.land_split_0.5.mz")
land_hr_shr_split_file     <- file.path(outputdir,"cell.land_split_0.5_share.mz")

load(paste0(outputdir, "/config.Rdata"))
################################################################################

if(length(map_file)==0) stop("Could not find map file!")
if(length(map_file)>1) {
  warning("More than one map file found. First occurrence will be used!")
  map_file <- map_file[1]
}


# Load input data
land_ini_lr  <- readGDX(gdx,"f10_land","f_land", format="first_found")[,"y1995",]
land_lr      <- land(gdx,sum=FALSE,level="cell")
land_ini_hr  <- read.magpie(land_hr_file)[,"y1995",]
magpie2luh2 <- data.frame(matrix(nrow=4,ncol=2))
names(magpie2luh2) <- c("MAgPIE","LUH2")
magpie2luh2[1,] <- c("crop","crop")
magpie2luh2[2,] <- c("past","past")
magpie2luh2[3,] <- c("past","range")
magpie2luh2[4,] <- c("urban","urban")
magpie2luh2[5,] <- c("primforest","primforest")
magpie2luh2[6,] <- c("secdforest","secdforest")
magpie2luh2[7,] <- c("forestry","forestry")
magpie2luh2[8,] <- c("other","primother")
magpie2luh2[9,] <- c("other","secdother")
land_ini_hr <- madrat::toolAggregate(land_ini_hr, magpie2luh2, from="LUH2", to="MAgPIE",dim = 3.1)
land_ini_hr  <- land_ini_hr[,,getNames(land_lr)]
if(any(land_ini_hr < 0)) {
  warning(paste0("Negative values in inital high resolution dataset detected and set to 0. Check the file ",land_hr_file))
  land_ini_hr[which(land_ini_hr < 0,arr.ind = T)] <- 0
}

#read in hr urban land
if (cfg$gms$urban == "exo_nov21" ) {
urban_land_hr  <- read.magpie(urban_land_hr_file)
ssp <- cfg$gms$c09_gdp_scenario
urban_land_hr <- urban_land_hr[,,ssp]
getNames(urban_land_hr) <- "urban"
} else if (cfg$gms$urban == "static"){
  urban_land_hr <- "static"
}

# account for country-specific set-aside shares in post-processing
iso <- readGDX(gdx, "iso")
set_aside_iso <- readGDX(gdx,"policy_countries30")
set_aside_select <- readGDX(gdx, "s30_set_aside_shr")
set_aside_noselect <- readGDX(gdx, "s30_set_aside_shr_noselect")
set_aside_shr <- new.magpie(iso, fill = set_aside_noselect)
set_aside_shr[set_aside_iso,,] <- set_aside_select

avl_cropland_hr <- file.path(outputdir, "avl_cropland_0.5.mz")       # available cropland (at high resolution)
marginal_land <- cfg$gms$c30_marginal_land                      # marginal land scenario
target_year <- cfg$gms$c30_set_aside_target                     # target year of set aside policy (default: "none")
set_aside_fader  <- readGDX(gdx,"f30_set_aside_fader", format="first_found")[,,target_year]

# Start interpolation (use interpolateAvlCroplandWeighted from luscale)
print("Disaggregation")
land_hr <- interpolateAvlCroplandWeighted(x          = land_lr,
                                          x_ini_lr   = land_ini_lr,
                                          x_ini_hr   = land_ini_hr,
                                          avl_cropland_hr = avl_cropland_hr,
                                          map        = map_file,
                                          marginal_land = marginal_land,
                                          set_aside_shr = set_aside_shr,
                                          set_aside_fader = set_aside_fader,
                                          urban_land_hr = urban_land_hr)

# Write outputs

.dissagcrop <- function(gdx, land_hr, map) {
  message("Disaggregation crop types")
  area     <- croparea(gdx, level="cell", products="kcr",
                       product_aggr=FALSE,water_aggr = FALSE)
  area_shr <- area/(dimSums(area,dim=3) + 10^-10)

  # calculate share of crop land on total cell area
  crop_shr <- land_hr/dimSums(land_hr, dim=3)
  crop_shr <- setNames(crop_shr[,getYears(area_shr),"crop"],NULL)
  # calculate crop area as share of total cell area
  area_shr_hr <- madrat::toolAggregate(area_shr, map, to="cell") * crop_shr
  return(area_shr_hr)
}

.tmpwrite <- function(x,file,comment,message) {
  write.magpie(x, file, comment=comment)
  write.magpie(x, sub(".mz",".nc",file), comment=comment, verbose=FALSE)
}

.tmpwrite(land_hr, land_hr_out_file, comment="unit: Mha per grid-cell",
          message="Write outputs cell.land")
.tmpwrite(land_hr/dimSums(land_hr,dim=3.1), land_hr_share_out_file,
          comment="unit: grid-cell land area fraction",
          message="Write outputs cell.land_share")

area_shr_hr <- .dissagcrop(gdx, land_hr, map=map_file)

.tmpwrite(area_shr_hr, croparea_hr_share_out_file,
          comment="unit: grid-cell land area fraction",
          message="Write outputs cell.cropara_share")


.split <- function(area_shr_hr, land_hr, land_hr_split_file,
                       land_hr_shr_split_file,map) {
  land_hr <- land_hr[,getYears(area_shr_hr),]
  area_hr <- area_shr_hr*dimSums(land_hr, dim=3)

  # replace crop in land_hr in with crop_kfo_rf, crop_kfo_ir, crop_kbe_rf
  # and crop_kbe_ir
  kbe <- c("betr","begr")
  kfo <- setdiff(getNames(area_hr,dim=1),kbe)
  crop_kfo_rf <- setNames(dimSums(area_hr[,,kfo][,,"rainfed"],dim=3),
                          "crop_kfo_rf")
  crop_kfo_ir <- setNames(dimSums(area_hr[,,kfo][,,"irrigated"],dim=3),
                          "crop_kfo_ir")
  crop_kbe_rf <- setNames(dimSums(area_hr[,,kbe][,,"rainfed"],dim=3),
                          "crop_kbe_rf")
  crop_kbe_ir <- setNames(dimSums(area_hr[,,kbe][,,"irrigated"],dim=3),
                          "crop_kbe_ir")
  crop_hr <- mbind(crop_kfo_rf,crop_kfo_ir,crop_kbe_rf,crop_kbe_ir)
  #drop crop
  land_hr <- land_hr[,,"crop",invert=TRUE]
  #combine land_hr with crop_hr.
  land_hr <- mbind(crop_hr,land_hr)

  # split "forestry" into timber plantations, pre-scribed afforestation (NPi/NDC) and endogenous afforestation (CO2 price driven)
  message("Disaggregation Forestry")
  farea     <- dimSums(landForestry(gdx, level="cell"),dim="ac")
  farea_shr <- farea/(dimSums(farea,dim=3) + 10^-10)
  # calculate forestry area as share of total cell area
  farea_hr <- madrat::toolAggregate(farea_shr, map, to="cell") * setNames(land_hr[,,"forestry"],NULL)
  #check
  if (abs(sum(dimSums(farea_hr,dim=3)-setNames(land_hr[,,"forestry"],NULL),na.rm=T)) > 0.1) warning("large Difference in crop disaggregation detected!")
  #rename
  df <- data.frame(matrix(nrow=3,ncol=2))
  names(df) <- c("internal","output")
  df[1,] <- c("aff","PlantedForest_Afforestation")
  df[2,] <- c("ndc","PlantedForest_NPiNDC")
  df[3,] <- c("plant","PlantedForest_Timber")
  farea_hr <- madrat::toolAggregate(farea_hr, df, from="internal", to="output",dim = 3.1)

  #drop forestry
  land_hr <- land_hr[,,"forestry",invert=TRUE]
  #combine land_hr with farea_hr
  land_hr <- mbind(land_hr,farea_hr)

  #write landpool
  .tmpwrite(land_hr, land_hr_split_file,
            comment="unit: Mha per grid-cell",
            message="Write cropsplit land area")

  .tmpwrite(land_hr/dimSums(land_hr,dim=3), land_hr_shr_split_file,
            comment="unit: grid-cell land area fraction",
            message="Write cropsplit land area share")
}

.split(area_shr_hr, land_hr, land_hr_split_file,land_hr_shr_split_file,map=map_file)
