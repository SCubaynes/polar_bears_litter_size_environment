#==============================================================================#
#                                                                              #
#                   Models with only sea ice retreat day                       #
#                                                                              #
#==============================================================================#

library(tidyverse)
library(lubridate)
library(mlogit)
library(viridis)
library(ggmcmc)
library(gridExtra)
library(nimble)
Sys.setenv(LANG = "en")

# READY VARIABLES ===========================================================
# CR data
CR_data <- read_csv("06_processed_data/CR_data/CR_f_clean.csv")

# Sea ice data
sea_ice_data <- read_csv("06_processed_data/sea_ice_data/retreat_advance_ice_free_days_E.csv")
sea_ice_data <- data.frame(sea_ice_data,
                           day_retreat_previous = c(NA, sea_ice_data$day_retreat[-nrow(sea_ice_data)]),
                           day_retreat_2y_prior = c(NA, NA, sea_ice_data$day_retreat[-c(nrow(sea_ice_data),
                                                                                        nrow(sea_ice_data) - 1)]))


data_model <- CR_data %>%
  left_join(x = CR_data,
            y = sea_ice_data,
            by = "year") %>%
  filter(year != 1992)  %>% # Remove the captures from 1992 since I can't calculate the ice free days in 1991
  filter(year != 1993) # Same 


# build dataset

# The variables will be stored in lists because JAGS requires lists
y <- factor(as.numeric(data_model$cub_number_2))
summary(y)

# Renumérotation des années
{year <- data_model$year
  year <- factor(year) # laisse tomber les modalites inutiles 
  year2 <- NULL
  for (i in 1:length(year)){
    year2 <- c(year2, which(year[i] == levels(year)))
  }
  year <- factor(year2)
  nbyear <- length(levels(year))
  year
}

# on renumerote les individus
{id_fem <- data_model$ID_NR
  id_fem <- factor(id_fem) 
  id_fem2 <- NULL
  for (i in 1:length(id_fem)){
    id_fem2 <- c(id_fem2,which(id_fem[i]==levels(id_fem)))
  }
  id_fem <- factor(id_fem2)
  nbind <- length(levels(id_fem))
  id_fem
}

N <- length(y) # nb of reproductive events
J <- length(levels(y)) # number of categories

my.constants <- list(N = length(y), # nb of females captured
                     J = length(levels(y)),
                     year = as.numeric(year),
                     nbyear = nbyear) 

# Load the JAGS models + the ancillary functions
source("05_script/models/1_sea_ice/1.2_Nimble_day_sea_ice_retreat.R")
source("05_script/models/functions_for_models_Nimble.R")





# RUN THE MODELS ===============================================================

# A. Null model ================================================================

model_code <- "null_model"
mode <- ""

load(file = paste0("07_results/01_interim_results/model_outputs/", 
                   model_code, toupper(mode), ".RData"))

get(paste0("fit_", model_code, mode))$WAIC
# 1083.937






# B. Sea ice retreat day  t-1 ==================================================

# ~ 1. Effect only on 1cub VS 0cubs (1.2.2_E_1c_VS_0c) -------------------------

# ~~~ a. Run the model ---------------------------------------------------------

{model_code <- "1.2.2_E"
effect <- "1c_VS_0c"

# Predictor
var <- data_model$day_retreat_previous
var_scaled <- (var - mean(var))/sd(var) 
var_short_name <- "day_retreat_previous_s"
var_full_name <- "Day of sea ice retreat in previous year"

# Are females without cubs taken into account ?
mode <- ""       # Yes
# mode <- "_bis"  # No
}

dat <- list(as.numeric(y), as.numeric(var_scaled))
names(dat) <- c("y", var_short_name)

# Define the parameters to estimate
params <- get_coefs_and_params(y, var_scaled, effect, mode)$params

# Generate starting values
coefs <- get_coefs_and_params(y, var_scaled, effect, mode)$coefs

inits <- function() list(a0 = coefs[1] + round(runif(n = 1, -1, 1))/10, 
                         b0 = coefs[2] + round(runif(n = 1, -1, 1))/10, 
                         a1 = coefs[3] + round(runif(n = 1, -1, 1))/10,
                         sigma1 = runif(1))



# Run the model
start <- Sys.time()
assign(x = paste0("fit_", model_code, "_effect_", effect, mode),
       value = nimbleMCMC(code = get(paste0("model_", model_code, "_effect_", effect, mode)),     # model code  
                          data = dat,                                   
                          constants = my.constants,        
                          inits = inits,          
                          monitors = params,   # parameters to monitor
                          thin = 10,
                          niter = 25000,                  # nb iterations
                          nburnin = 5000,              # length of the burn-in
                          nchains = 2,
                          summary = TRUE,
                          WAIC = TRUE))
end <- Sys.time()
end - start




get(paste0("fit_", model_code, "_effect_", effect, mode))$WAIC
# 1085.682

save(list = paste0("fit_", model_code, "_effect_", effect, mode), 
     file = paste0("07_results/01_interim_results/model_outputs/model_", 
                   model_code, "_effect_", effect, toupper(mode), ".RData"))



# ~~~ b. Check convergence -----------------------------------------------------
load(file = paste0("07_results/01_interim_results/model_outputs/model_", 
                   model_code, "_effect_", effect, toupper(mode), ".RData"))






# ~~~ c. Plot the model --------------------------------------------------------
load(file = paste0("07_results/01_interim_results/model_outputs/model_", 
                   model_code, "_effect_", effect, toupper(mode), ".RData"))



# Plot
ggplot(data = get(paste0("fit_", model_code, "_effect_", effect, mode, "_for_plot")), 
       aes(x = var, y = value, group = name, linetype = type, color = as.factor(cub_number))) +
  geom_line() +
  scale_color_viridis(discrete = TRUE,                       
                      labels = color_labels) +
  scale_linetype_manual(limits = c("mean", "credible_interval"),
                        values = c("solid", "dotted"),
                        labels = c("Mean", "CI")) +
  theme_bw() +
  labs(x = var_full_name,
       y = "Probability", 
       color = "",
       linetype = "") 

ggsave(filename = paste0("07_results/01_interim_results/model_outputs/graphs/model_", 
                         model_code, "_effect_", effect, toupper(mode), ".png"),
       width = 6, height = 3)


rm(list = c(paste0("fit_", model_code, "_effect_", effect, mode)))
rm(model_code, effect, dat, params, coefs, inits, 
   var, var_scaled, var_short_name, var_full_name)
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++#
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++#




# ~ 2. Effect only on 2-3cub VS 0cubs (1.2.2_E_2-3c_VS_0c) ---------------------

# ~~~ a. Run the model ---------------------------------------------------------


{model_code <- "1.2.2_E"
effect <- "2_3c_VS_0c"

# Predictor
var <- data_model$day_retreat_previous
var_scaled <- (var - mean(var))/sd(var) 
var_short_name <- "day_retreat_previous_s"
var_full_name <- "Day of sea ice retreat in previous year"

# Are females without cubs taken into account ?
mode <- ""       # Yes
# mode <- "_bis"  # No
}

dat <- list(as.numeric(y), as.numeric(var_scaled))
names(dat) <- c("y", var_short_name)

# Define the parameters to estimate
params <- get_coefs_and_params(y, var_scaled, effect, mode)$params

# Generate starting values
coefs <- get_coefs_and_params(y, var_scaled, effect, mode)$coefs

inits <- function() list(a0 = coefs[1] + round(runif(n = 1, -1, 1))/10, 
                         b0 = coefs[2] + round(runif(n = 1, -1, 1))/10, 
                         b1 = coefs[3] + round(runif(n = 1, -1, 1))/10,
                         sigma1 = runif(1))



# Run the model
start <- Sys.time()
assign(x = paste0("fit_", model_code, "_effect_", effect, mode),
       value = nimbleMCMC(code = get(paste0("model_", model_code, "_effect_", effect, mode)),     # model code  
                          data = dat,                                   
                          constants = my.constants,        
                          inits = inits,          
                          monitors = params,   # parameters to monitor
                          thin = 10,
                          niter = 25000,                  # nb iterations
                          nburnin = 5000,              # length of the burn-in
                          nchains = 2,
                          summary = TRUE,
                          WAIC = TRUE))
end <- Sys.time()
end - start




get(paste0("fit_", model_code, "_effect_", effect, mode))$WAIC
# 1085.007

save(list = paste0("fit_", model_code, "_effect_", effect, mode), 
     file = paste0("07_results/01_interim_results/model_outputs/model_", 
                   model_code, "_effect_", effect, toupper(mode), ".RData"))



# ~~~ b. Check convergence -----------------------------------------------------
load(file = paste0("07_results/01_interim_results/model_outputs/model_", 
                   model_code, "_effect_", effect, toupper(mode), ".RData"))

rm(list = c(paste0("fit_", model_code, "_effect_", effect, mode)))
rm(model_code, effect, dat, params, coefs, inits, 
   var, var_scaled, var_short_name, var_full_name)
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++#
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++#




# ~ 3. Common effect of 1c VS 0 and of 2-3c VS 0 (1.2.2_E_common) --------------

# ~~~ a. Run the model ---------------------------------------------------------

{model_code <- "1.2.2_E"
effect <- "common"

# Predictor
var <- data_model$day_retreat_previous
var_scaled <- (var - mean(var))/sd(var) 
var_short_name <- "day_retreat_previous_s"
var_full_name <- "Day of sea ice retreat in previous year"

# Are females without cubs taken into account ?
mode <- ""       # Yes
# mode <- "_bis"  # No
}

dat <- list(as.numeric(y), as.numeric(var_scaled))
names(dat) <- c("y", var_short_name)

# Define the parameters to estimate
params <- get_coefs_and_params(y, var_scaled, effect, mode)$params
# params <- c("a0", "b0", "b1", "sigma1", "eps1") 

# Generate starting values
coefs <- get_coefs_and_params(y, var_scaled, effect, mode)$coefs

inits <- function() list(a0 = coefs[1] + round(runif(n = 1, -1, 1))/10, 
                         b0 = coefs[2] + round(runif(n = 1, -1, 1))/10, 
                         a1 = coefs[3] + round(runif(n = 1, -1, 1))/10,
                         sigma1 = runif(1))



# Run the model
start <- Sys.time()
assign(x = paste0("fit_", model_code, "_effect_", effect, mode),
       value = nimbleMCMC(code = get(paste0("model_", model_code, "_effect_", effect, mode)),     # model code  
                          data = dat,                                   
                          constants = my.constants,        
                          inits = inits,          
                          monitors = params,   # parameters to monitor
                          thin = 10,
                          niter = 25000,                  # nb iterations
                          nburnin = 5000,              # length of the burn-in
                          nchains = 2,
                          summary = TRUE,
                          WAIC = TRUE))
end <- Sys.time()
end - start




get(paste0("fit_", model_code, "_effect_", effect, mode))$WAIC
# 1082.481

save(list = paste0("fit_", model_code, "_effect_", effect, mode), 
     file = paste0("07_results/01_interim_results/model_outputs/model_", 
                   model_code, "_effect_", effect, toupper(mode), ".RData"))



# ~~~ b. Check convergence -----------------------------------------------------
load(file = paste0("07_results/01_interim_results/model_outputs/model_", 
                   model_code, "_effect_", effect, toupper(mode), ".RData"))

rm(list = c(paste0("fit_", model_code, "_effect_", effect, mode)))
rm(model_code, effect, dat, params, coefs, inits, 
   var, var_scaled, var_short_name, var_full_name)
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++#
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++#







# ~ 4. Distinct effect of 1c VS 0 and of 2-3c VS 0 (1.2.2_E_distinct) --------------

# ~~~ a. Run the model ---------------------------------------------------------

{model_code <- "1.2.2_E"
effect <- "distinct"

# Predictor
var <- data_model$day_retreat_previous
var_scaled <- (var - mean(var))/sd(var) 
var_short_name <- "day_retreat_previous_s"
var_full_name <- "Day of sea ice retreat in previous year"

# Are females without cubs taken into account ?
mode <- ""       # Yes
# mode <- "_bis"  # No
}

dat <- list(as.numeric(y), as.numeric(var_scaled))
names(dat) <- c("y", var_short_name)

# Define the parameters to estimate
params <- get_coefs_and_params(y, var_scaled, effect, mode)$params

# Generate starting values
coefs <- get_coefs_and_params(y, var_scaled, effect, mode)$coefs

inits <- function() list(a0 = coefs[1] + round(runif(n = 1, -1, 1))/10, 
                         b0 = coefs[2] + round(runif(n = 1, -1, 1))/10, 
                         a1 = coefs[3] + round(runif(n = 1, -1, 1))/10,
                         b1 = coefs[4] + round(runif(n = 1, -1, 1))/10,
                         sigma1 = runif(1))



# Run the model
start <- Sys.time()
assign(x = paste0("fit_", model_code, "_effect_", effect, mode),
       value = nimbleMCMC(code = get(paste0("model_", model_code, "_effect_", effect, mode)),     # model code  
                          data = dat,                                   
                          constants = my.constants,        
                          inits = inits,          
                          monitors = params,   # parameters to monitor
                          thin = 10,
                          niter = 25000,                  # nb iterations
                          nburnin = 5000,              # length of the burn-in
                          nchains = 2,
                          summary = TRUE,
                          WAIC = TRUE))
end <- Sys.time()
end - start




get(paste0("fit_", model_code, "_effect_", effect, mode))$WAIC
# 1084.289

save(list = paste0("fit_", model_code, "_effect_", effect, mode), 
     file = paste0("07_results/01_interim_results/model_outputs/model_", 
                   model_code, "_effect_", effect, toupper(mode), ".RData"))



# ~~~ b. Check convergence -----------------------------------------------------
load(file = paste0("07_results/01_interim_results/model_outputs/model_", 
                   model_code, "_effect_", effect, toupper(mode), ".RData"))

rm(list = c(paste0("fit_", model_code, "_effect_", effect, mode)))
rm(model_code, effect, dat, params, coefs, inits, 
   var, var_scaled, var_short_name, var_full_name)
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++#
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++#






# C. Day retreat t-2 =========================================================

# ~ 1. Effect only on 1cub VS 0cubs (1.2.3_E_1c_VS_0c) -------------------------

# ~~~ a. Run the model ---------------------------------------------------------

{model_code <- "1.2.3_E"
effect <- "1c_VS_0c"

# Predictor
var <- data_model$day_retreat_2y_prior
var_scaled <- (var - mean(var))/sd(var) 
var_short_name <- "day_retreat_2y_prior_s"
var_full_name <- "Day of sea ice retreat two years before"

# Are females without cubs taken into account ?
mode <- ""       # Yes
# mode <- "_bis"  # No
}

dat <- list(as.numeric(y), as.numeric(var_scaled))
names(dat) <- c("y", var_short_name)

# Define the parameters to estimate
params <- get_coefs_and_params(y, var_scaled, effect, mode)$params

# Generate starting values
coefs <- get_coefs_and_params(y, var_scaled, effect, mode)$coefs

inits <- function() list(a0 = coefs[1] + round(runif(n = 1, -1, 1))/10, 
                         b0 = coefs[2] + round(runif(n = 1, -1, 1))/10, 
                         a1 = coefs[3] + round(runif(n = 1, -1, 1))/10,
                         sigma1 = runif(1))



# Run the model
start <- Sys.time()
assign(x = paste0("fit_", model_code, "_effect_", effect, mode),
       value = nimbleMCMC(code = get(paste0("model_", model_code, "_effect_", effect, mode)),     # model code  
                          data = dat,                                   
                          constants = my.constants,        
                          inits = inits,          
                          monitors = params,   # parameters to monitor
                          thin = 10,
                          niter = 20000,                  # nb iterations
                          nburnin = 5000,              # length of the burn-in
                          nchains = 2,
                          summary = TRUE,
                          WAIC = TRUE))
end <- Sys.time()
end - start




get(paste0("fit_", model_code, "_effect_", effect, mode))$WAIC
# 1085.376

save(list = paste0("fit_", model_code, "_effect_", effect, mode), 
     file = paste0("07_results/01_interim_results/model_outputs/model_", 
                   model_code, "_effect_", effect, toupper(mode), ".RData"))



# ~~~ b. Check convergence -----------------------------------------------------
load(file = paste0("07_results/01_interim_results/model_outputs/model_", 
                   model_code, "_effect_", effect, toupper(mode), ".RData"))

rm(list = c(paste0("fit_", model_code, "_effect_", effect, mode)))
rm(model_code, effect, dat, params, coefs, inits, 
   var, var_scaled, var_short_name, var_full_name)

#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++#
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++#




# ~ 2. Effect only on 2-3cub VS 0cubs (1.2.3_E_2-3c_VS_0c) ---------------------

# ~~~ a. Run the model ---------------------------------------------------------

{model_code <- "1.2.3_E"
effect <- "2_3c_VS_0c"

# Predictor
var <- data_model$day_retreat_2y_prior
var_scaled <- (var - mean(var))/sd(var) 
var_short_name <- "day_retreat_2y_prior_s"
var_full_name <- "Day of sea ice retreat two years before"

# Are females without cubs taken into account ?
mode <- ""       # Yes
# mode <- "_bis"  # No
}

dat <- list(as.numeric(y), as.numeric(var_scaled))
names(dat) <- c("y", var_short_name)

# Define the parameters to estimate
params <- get_coefs_and_params(y, var_scaled, effect, mode)$params

# Generate starting values
coefs <- get_coefs_and_params(y, var_scaled, effect, mode)$coefs

inits <- function() list(a0 = coefs[1] + round(runif(n = 1, -1, 1))/10, 
                         b0 = coefs[2] + round(runif(n = 1, -1, 1))/10, 
                         b1 = coefs[3] + round(runif(n = 1, -1, 1))/10,
                         sigma1 = runif(1))



# Run the model
start <- Sys.time()
assign(x = paste0("fit_", model_code, "_effect_", effect, mode),
       value = nimbleMCMC(code = get(paste0("model_", model_code, "_effect_", effect, mode)),     # model code  
                          data = dat,                                   
                          constants = my.constants,        
                          inits = inits,          
                          monitors = params,   # parameters to monitor
                          thin = 10,
                          niter = 20000,                  # nb iterations
                          nburnin = 5000,              # length of the burn-in
                          nchains = 2,
                          summary = TRUE,
                          WAIC = TRUE))
end <- Sys.time()
end - start


get(paste0("fit_", model_code, "_effect_", effect, mode))$WAIC
# 1084.96

save(list = paste0("fit_", model_code, "_effect_", effect, mode), 
     file = paste0("07_results/01_interim_results/model_outputs/model_", 
                   model_code, "_effect_", effect, toupper(mode), ".RData"))



# ~~~ b. Check convergence -----------------------------------------------------
load(file = paste0("07_results/01_interim_results/model_outputs/model_", 
                   model_code, "_effect_", effect, toupper(mode), ".RData"))

rm(list = c(paste0("fit_", model_code, "_effect_", effect, mode)))
rm(model_code, effect, dat, params, coefs, inits, 
   var, var_scaled, var_short_name, var_full_name)

#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++#
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++#




# ~ 3. Common effect of 1c VS 0 and of 2-3c VS 0 (1.2.3_E_common) --------------

# ~~~ a. Run the model ---------------------------------------------------------

{model_code <- "1.2.3_E"
effect <- "common"

# Predictor
var <- data_model$day_retreat_2y_prior
var_scaled <- (var - mean(var))/sd(var) 
var_short_name <- "day_retreat_2y_prior_s"
var_full_name <- "Day of sea ice retreat two years before"

# Are females without cubs taken into account ?
mode <- ""       # Yes
# mode <- "_bis"  # No
}

dat <- list(as.numeric(y), as.numeric(var_scaled))
names(dat) <- c("y", var_short_name)

# Define the parameters to estimate
params <- get_coefs_and_params(y, var_scaled, effect, mode)$params

# Generate starting values
coefs <- get_coefs_and_params(y, var_scaled, effect, mode)$coefs

inits <- function() list(a0 = coefs[1] + round(runif(n = 1, -1, 1))/10, 
                         b0 = coefs[2] + round(runif(n = 1, -1, 1))/10, 
                         a1 = coefs[3] + round(runif(n = 1, -1, 1))/10,
                         sigma1 = runif(1))



# Run the model
start <- Sys.time()
assign(x = paste0("fit_", model_code, "_effect_", effect, mode),
       value = nimbleMCMC(code = get(paste0("model_", model_code, "_effect_", effect, mode)),     # model code  
                          data = dat,                                   
                          constants = my.constants,        
                          inits = inits,          
                          monitors = params,   # parameters to monitor
                          thin = 10,
                          niter = 20000,                  # nb iterations
                          nburnin = 5000,              # length of the burn-in
                          nchains = 2,
                          summary = TRUE,
                          WAIC = TRUE))
end <- Sys.time()
end - start


get(paste0("fit_", model_code, "_effect_", effect, mode))$WAIC
# 1080.501

save(list = paste0("fit_", model_code, "_effect_", effect, mode), 
     file = paste0("07_results/01_interim_results/model_outputs/model_", 
                   model_code, "_effect_", effect, toupper(mode), ".RData"))



# ~~~ b. Check convergence -----------------------------------------------------
load(file = paste0("07_results/01_interim_results/model_outputs/model_", 
                   model_code, "_effect_", effect, toupper(mode), ".RData"))

rm(list = c(paste0("fit_", model_code, "_effect_", effect, mode)))
rm(model_code, effect, dat, params, coefs, inits, 
   var, var_scaled, var_short_name, var_full_name)

#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++#
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++#







# ~ 4. Distinct effect of 1c VS 0 and of 2-3c VS 0 (1.2.3_E_distinct) ----------

# ~~~ a. Run the model ---------------------------------------------------------

{model_code <- "1.2.3_E"
effect <- "distinct"

# Predictor
var <- data_model$day_retreat_2y_prior
var_scaled <- (var - mean(var))/sd(var) 
var_short_name <- "day_retreat_2y_prior_s"
var_full_name <- "Day of sea ice retreat two years before"

# Are females without cubs taken into account ?
mode <- ""       # Yes
# mode <- "_bis"  # No
}

dat <- list(as.numeric(y), as.numeric(var_scaled))
names(dat) <- c("y", var_short_name)

# Define the parameters to estimate
params <- get_coefs_and_params(y, var_scaled, effect, mode)$params
# params <- c("a0", "b0", "b1", "sigma1", "eps1") 

# Generate starting values
coefs <- get_coefs_and_params(y, var_scaled, effect, mode)$coefs

inits <- function() list(a0 = coefs[1] + round(runif(n = 1, -1, 1))/10, 
                         b0 = coefs[2] + round(runif(n = 1, -1, 1))/10, 
                         a1 = coefs[3] + round(runif(n = 1, -1, 1))/10,
                         b1 = coefs[4] + round(runif(n = 1, -1, 1))/10,
                         sigma1 = runif(1))



# Run the model
start <- Sys.time()
assign(x = paste0("fit_", model_code, "_effect_", effect, mode),
       value = nimbleMCMC(code = get(paste0("model_", model_code, "_effect_", effect, mode)),     # model code  
                          data = dat,                                   
                          constants = my.constants,        
                          inits = inits,          
                          monitors = params,   # parameters to monitor
                          thin = 10,
                          niter = 20000,                  # nb iterations
                          nburnin = 5000,              # length of the burn-in
                          nchains = 2,
                          summary = TRUE,
                          WAIC = TRUE))
end <- Sys.time()
end - start




get(paste0("fit_", model_code, "_effect_", effect, mode))$WAIC
# 1085.852

save(list = paste0("fit_", model_code, "_effect_", effect, mode), 
     file = paste0("07_results/01_interim_results/model_outputs/model_", 
                   model_code, "_effect_", effect, toupper(mode), ".RData"))



# ~~~ b. Check convergence -----------------------------------------------------
load(file = paste0("07_results/01_interim_results/model_outputs/model_", 
                   model_code, "_effect_", effect, toupper(mode), ".RData"))

rm(list = c(paste0("fit_", model_code, "_effect_", effect, mode)))
rm(model_code, effect, dat, params, coefs, inits, 
   var, var_scaled, var_short_name, var_full_name)

#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++#
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++#