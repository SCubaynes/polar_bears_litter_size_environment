#==============================================================================#
#                                                                              #
#                      Function to run and interpret models                    #
#                                                                              #
#==============================================================================#


define_params <- function(mode, slope) {
  if (mode == "_bis") {
    if(slope == "common") {
      params <- c("b0","b1", "c0", "sigma1", "eps1")
      nb.beta <- 3
    } else {
      params <- c("b0","b1", "c0", "c1", "sigma1", "eps1")
      nb.beta <- 4
    }
  } else {
    if(slope == "common") {
      params <- c("a0", "a1", "b0", "c0", "sigma1" ,"eps1")
      nb.beta <- 4
    } else {
      params <- c("a0", "a1", "b0","b1", "c0", "c1", "sigma1","eps1")
      nb.beta <- 6
    }
  }
  return(list(params, nb.beta))
}


get_inits <- function(y, var_scaled, mode, slope) {
  temp.dat <- data.frame(y = y, var_scaled = var_scaled)
  temp.dat$yfac <- as.factor(temp.dat$y)   # Ajout de Y en facteur
  mnl.dat <- mlogit.data(temp.dat, varying = NULL, choice = "yfac", shape = "wide") 
  mlogit.mod <- mlogit(yfac ~ 1| var_scaled, 
                       data = mnl.dat, 
                       reflevel = ifelse(mode == "_bis", "1", "0"))
  
  coefs <- as.vector(summary(mlogit.mod)$coefficients)
  if (mode == "_bis") {
    
    if(slope == "common") {
      inits1 <- list(b0 = coefs[1], c0 = coefs[2], 
                     b1 = coefs[3],
                     sigma1 = runif(1))
      inits2 <- list(b0 = coefs[1] + 0.1, c0 = coefs[2] - 0.1, 
                     b1 = coefs[4] + 0.1,
                     sigma1 = runif(1))
    } else {
      inits1 <- list(b0 = coefs[1], c0 = coefs[2], 
                     b1 = coefs[3], c1 = coefs[4],
                     sigma1 = runif(1))
      inits2 <- list(b0 = coefs[1] + 0.1, c0 = coefs[2] - 0.1, 
                     b1 = coefs[4] + 0.1, c1 = coefs[4] - 0.1,
                     sigma1 = runif(1))
    }
  }  else {
    
    if(slope == "common") {
      inits1 <- list(a0 = coefs[1], b0 = coefs[2], c0 = coefs[3],
                     a1 = coefs[4],
                     sigma1 = runif(1))
      inits2 <- list(a0 = coefs[1] + 0.1, b0 = coefs[2] - 0.1, c0 = coefs[3] + 0.1,
                     a1 = coefs[4] -0.1,
                     sigma1 = runif(1))
      
    } else {
      inits1 <- list(a0 = coefs[1], b0 = coefs[2], c0 = coefs[3],
                     a1 = coefs[4], b1 = coefs[5], c1 = coefs[6],
                     sigma1 = runif(1))
      inits2 <- list(a0 = coefs[1] + 0.1, b0 = coefs[2] - 0.1, c0 = coefs[3] + 0.1,
                     a1 = coefs[4] - 0.1, b1 = coefs[5] + 0.1, c1 = coefs[6] - 0.1,
                     sigma1 = runif(1))
    }
  }
  inits <- list(inits1, inits2)
  return(inits)
}


check_convergence <- function(jags_output, model_code, slope, mode) {
  processed_output <- ggs(as.mcmc(jags_output)) %>%
    filter(Parameter %in% c("a0", "a1", "a2", "b0", "b1", "c0", "c1", "deviance"))
  
  f1 <- ggs_traceplot(processed_output) + 
    theme_bw() +
    theme(legend.position = "none")
  f2 <- ggs_density(processed_output) + 
    theme_bw()
  f3 <- ggs_running(processed_output) + 
    theme_bw() +
    theme(legend.position = "none")
  x <- grid.arrange(f1, f2, f3, ncol = 3, nrow = 1)
  
  nbr_rows <- length(unique(processed_output$Parameter))
  
  ggsave(x,
         filename = paste0("07_results/01_interim_results/model_outputs/graphs/diagnostic_plots/model_",
                           model_code, "_", slope, toupper(mode), ".png"),
         width = 17.5, height = 2.5*nbr_rows)
  
}


get_probabilities <- function(model_code, mode, slope, var_scaled, var) {
  res <- get(paste0("fit_", model_code, "_", slope, mode))$BUGSoutput$sims.matrix
  
  # If females without cubs are included
  if(mode == "") {
    if(slope == "common") {
      b1cub <- res[, c(1, 2)]
      b2cub <- res[, c(3, 2)] 
      b3cub <- res[, c(4, 2)] 
    } else {
      b1cub <- res[, c(1, 2)]
      b2cub <- res[, c(3, 4)]
      b3cub <- res[, c(5, 6)]
    }
    range <- range(var_scaled)
    
    lengthgrid <- 100
    grid_scaled <- seq(from = range[1] - 0.1*(range[2] - range[1]), 
                       to = range[2] + 0.1*(range[2] - range[1]), 
                       length = lengthgrid)
    
    grid <- grid_scaled * sd(var) + mean(var)
    
    
    q0cub <- q1cub <- q2cub <- q3cub <- matrix(data = NA, 
                                               nrow = dim(b2cub)[1], 
                                               ncol = lengthgrid)
    for (i in 1:lengthgrid) {
      for (j in 1:dim(b2cub)[1]) {
        q0cub[j, i] <- exp(0)
        q1cub[j, i] <- exp(b1cub[j, 1] + b1cub[j, 2] * grid_scaled[i])	
        q2cub[j, i] <- exp(b2cub[j, 1] + b2cub[j, 2] * grid_scaled[i])	
        q3cub[j, i] <- exp(b3cub[j, 1] + b3cub[j, 2] * grid_scaled[i])		
      }
    }
    # Backtransform
    p0cub <- p1cub <- p2cub <- p3cub <- matrix(NA, dim(b2cub)[1], lengthgrid)
    for (i in 1:lengthgrid){
      for (j in 1:dim(b2cub)[1]){
        norm <- (q0cub[j, i] + q1cub[j, i] + q2cub[j, i] + q3cub[j,i])
        p0cub[j, i] <- q0cub[j, i]/norm
        p1cub[j, i] <- q1cub[j, i]/norm
        p2cub[j, i] <- q2cub[j, i]/norm
        p3cub[j, i] <- q3cub[j, i]/norm
      }
    }
    df.for.plot <- data.frame(var = grid,
                              mean_p_0_cub = apply(p0cub, 2, mean),
                              mean_p_1_cub = apply(p1cub, 2, mean),
                              mean_p_2_cub = apply(p2cub, 2, mean),
                              mean_p_3_cub = apply(p3cub, 2, mean),
                              ci_p_0_cub_2.5 = apply(p0cub, 2, quantile, probs = 0.025),
                              ci_p_0_cub_97.5 = apply(p0cub, 2, quantile, probs = 0.975),
                              ci_p_1_cub_2.5 = apply(p1cub, 2, quantile, probs = 0.025),
                              ci_p_1_cub_97.5 = apply(p1cub, 2, quantile, probs = 0.975),
                              ci_p_2_cub_2.5 = apply(p2cub, 2, quantile, probs = 0.025),
                              ci_p_2_cub_97.5 = apply(p2cub, 2, quantile, probs = 0.975),
                              ci_p_3_cub_2.5 = apply(p3cub, 2, quantile, probs = 0.025),
                              ci_p_3_cub_97.5 = apply(p3cub, 2, quantile, probs = 0.975)) %>%
      pivot_longer(cols = c("mean_p_0_cub", "mean_p_1_cub", "mean_p_2_cub", "mean_p_3_cub",
                            "ci_p_0_cub_2.5", "ci_p_0_cub_97.5", 
                            "ci_p_1_cub_2.5", "ci_p_1_cub_97.5", 
                            "ci_p_2_cub_2.5", "ci_p_2_cub_97.5", 
                            "ci_p_3_cub_2.5", "ci_p_3_cub_97.5")) %>%
      mutate(cub_number = ifelse(name %in% c("mean_p_0_cub", "ci_p_0_cub_2.5", "ci_p_0_cub_97.5"), 0, 
                                 ifelse(name %in% c("mean_p_1_cub", "ci_p_1_cub_2.5", "ci_p_1_cub_97.5"), 1, 
                                        ifelse(name %in% c("mean_p_2_cub", "ci_p_2_cub_2.5", "ci_p_2_cub_97.5"), 2, 3))),
             type = ifelse(name %in% c("mean_p_0_cub", "mean_p_1_cub", "mean_p_2_cub", "mean_p_3_cub"), "mean", "credible_interval"))
    
    color_labels <- c("no cubs", "1 cub", "2 cubs", "3 cubs")
    
    
    # If females without cubs are excluded
  } else {
    if(slope == "common") {
      b2cub <- res[, c(1, 2)]
      b3cub <- res[, c(3, 2)] 
    } else {
      b2cub <- res[, c(1, 2)] 
      b3cub <- res[, c(3, 4)]
    }
    
    range <- range(var_scaled)
    
    lengthgrid <- 100
    grid_scaled <- seq(from = range[1] - 0.1*(range[2] - range[1]), 
                       to = range[2] + 0.1*(range[2] - range[1]), 
                       length = lengthgrid)
    
    grid <- grid_scaled * sd(var) + mean(var)
    
    q1cub <- q2cub <- q3cub <- matrix(data = NA, 
                                      nrow = dim(b2cub)[1], 
                                      ncol = lengthgrid)
    
    for (i in 1:lengthgrid){
      for (j in 1:dim(b2cub)[1]){
        q1cub[j, i] <- exp(0)
        q2cub[j, i] <- exp(b2cub[j, 1] + b2cub[j, 2] * grid_scaled[i])	
        q3cub[j, i] <- exp(b3cub[j, 1] + b3cub[j, 2] * grid_scaled[i])		
      }
    }
    
    # backtransform
    p1cub <- matrix(NA, dim(b2cub)[1], lengthgrid)
    p2cub <- p1cub
    p3cub <- p1cub
    for (i in 1:lengthgrid){
      for (j in 1:dim(b2cub)[1]){
        norm <- (q1cub[j, i] + q2cub[j, i] + q3cub[j,i])
        p1cub[j, i] <- q1cub[j, i]/norm
        p2cub[j, i] <- q2cub[j, i]/norm
        p3cub[j, i] <- q3cub[j, i]/norm
      }
    }
    df.for.plot <- data.frame(var = grid,
                              mean_p_1_cub = apply(p1cub, 2, mean),
                              mean_p_2_cub = apply(p2cub, 2, mean),
                              mean_p_3_cub = apply(p3cub, 2, mean),
                              ci_p_1_cub_2.5 = apply(p1cub, 2, quantile, probs = 0.025),
                              ci_p_1_cub_97.5 = apply(p1cub, 2, quantile, probs = 0.975),
                              ci_p_2_cub_2.5 = apply(p2cub, 2, quantile, probs = 0.025),
                              ci_p_2_cub_97.5 = apply(p2cub, 2, quantile, probs = 0.975),
                              ci_p_3_cub_2.5 = apply(p3cub, 2, quantile, probs = 0.025),
                              ci_p_3_cub_97.5 = apply(p3cub, 2, quantile, probs = 0.975)) %>%
      pivot_longer(cols = c("mean_p_1_cub", "mean_p_2_cub", "mean_p_3_cub",
                            "ci_p_1_cub_2.5", "ci_p_1_cub_97.5", 
                            "ci_p_2_cub_2.5", "ci_p_2_cub_97.5", 
                            "ci_p_3_cub_2.5", "ci_p_3_cub_97.5")) %>%
      mutate(cub_number = ifelse(name %in% c("mean_p_1_cub", "ci_p_1_cub_2.5", "ci_p_1_cub_97.5"), 1, 
                                 ifelse(name %in% c("mean_p_2_cub", "ci_p_2_cub_2.5", "ci_p_2_cub_97.5"), 2, 3)),
             type = ifelse(name %in% c("mean_p_1_cub", "mean_p_2_cub", 
                                       "mean_p_3_cub"), "mean", "credible_interval"))
    
    color_labels <- c("1 cub", "2 cubs", "3 cubs")
  }
  return(list(df.for.plot, color_labels))
}





get_probabilities_factor <- function(model_code, mode, slope, var_scaled, var) {
  res <- get(paste0("fit_", model_code, "_", slope, mode))$BUGSoutput$sims.matrix
  
  # If females without cubs are included
  if(mode == "") {
    if(slope == "common") {
      b1cub <- res[, c(1, 2)]
      b2cub <- res[, c(3, 2)] 
      b3cub <- res[, c(4, 2)] 
    } else {
      b1cub <- res[, c(1, 2)]
      b2cub <- res[, c(3, 4)] 
      b3cub <- res[, c(5, 6)] 
    }
    
    lengthgrid <- 2
    grid <- seq(from = 0,
                to = 1, 
                length = lengthgrid)
    
    q0cub <- q1cub <- q2cub <- q3cub <- matrix(data = NA, 
                                               nrow = dim(b2cub)[1], 
                                               ncol = lengthgrid)
    for (i in 1:lengthgrid){
      for (j in 1:dim(b2cub)[1]){
        q0cub[j, i] <- exp(0)
        q1cub[j, i] <- exp(b1cub[j, 1] + b1cub[j, 2] * grid[i])	
        q2cub[j, i] <- exp(b2cub[j, 1] + b2cub[j, 2] * grid[i])	
        q3cub[j, i] <- exp(b3cub[j, 1] + b3cub[j, 2] * grid[i])		
      }}
    # backtransform
    p0cub <- p1cub <- p2cub <- p3cub <- matrix(NA, dim(b2cub)[1], lengthgrid)
    for (i in 1:lengthgrid){
      for (j in 1:dim(b2cub)[1]){
        norm <- (q0cub[j, i] + q1cub[j, i] + q2cub[j, i] + q3cub[j,i])
        p0cub[j, i] <- q0cub[j, i]/norm
        p1cub[j, i] <- q1cub[j, i]/norm
        p2cub[j, i] <- q2cub[j, i]/norm
        p3cub[j, i] <- q3cub[j, i]/norm
      }
    }
    
    df.for.plot <- data.frame(var = c(rep(0, times = length(p1cub)/2),
                                      rep(1, times = length(p1cub)/2),
                                      rep(0, times = length(p1cub)/2),
                                      rep(1, times = length(p1cub)/2),
                                      rep(0, times = length(p1cub)/2),
                                      rep(1, times = length(p1cub)/2),
                                      rep(0, times = length(p1cub)/2),
                                      rep(1, times = length(p1cub)/2)),
                              probability = c(p0cub[, 1], p0cub[, 2],
                                              p1cub[, 1], p1cub[, 2],
                                              p2cub[, 1], p2cub[, 2],
                                              p3cub[, 1], p3cub[, 2]),
                              nbr_cub = c(rep("no cubs", times = length(p1cub)),
                                          rep("1 cub", times = length(p1cub)),
                                          rep("2 cubs", times = length(p1cub)),
                                          rep("3 cubs", times = length(p1cub)))) %>%
      mutate(nbr_cub = factor(nbr_cub,      # Reordering group factor levels
                              levels = c("no cubs", "1 cub", "2 cubs", "3 cubs")))
    color_labels <- c("no cubs", "1 cub", "2 cubs", "3 cubs")
    
    
    
    # If females without cubs are excluded
  } else {
    if(slope == "common") {
      b2cub <- res[, c(1, 2)]
      b3cub <- res[, c(3, 2)] 
    } else {
      b2cub <- res[, c(1, 2)] 
      b3cub <- res[, c(3, 4)]
    }
    
    range <- range(var_scaled)
    
    lengthgrid <- 2
    grid <- seq(from = 0,
                to = 1, 
                length = lengthgrid)
    
    q1cub <- q2cub <- q3cub <- matrix(data = NA, 
                                      nrow = dim(b2cub)[1], 
                                      ncol = lengthgrid)
    
    for (i in 1:lengthgrid){
      for (j in 1:dim(b2cub)[1]){
        q1cub[j, i] <- exp(0)
        q2cub[j, i] <- exp(b2cub[j, 1] + b2cub[j, 2] * grid[i])	
        q3cub[j, i] <- exp(b3cub[j, 1] + b3cub[j, 2] * grid[i])		
      }
    }
    
    # backtransform
    p1cub <- matrix(NA, dim(b2cub)[1], lengthgrid)
    p2cub <- p1cub
    p3cub <- p1cub
    for (i in 1:lengthgrid){
      for (j in 1:dim(b2cub)[1]){
        norm <- (q1cub[j, i] + q2cub[j, i] + q3cub[j,i])
        p1cub[j, i] <- q1cub[j, i]/norm
        p2cub[j, i] <- q2cub[j, i]/norm
        p3cub[j, i] <- q3cub[j, i]/norm
      }
    }
    df.for.plot <- data.frame(var = c(rep(0, times = length(p1cub)/2),
                                      rep(1, times = length(p1cub)/2),
                                      rep(0, times = length(p1cub)/2),
                                      rep(1, times = length(p1cub)/2),
                                      rep(0, times = length(p1cub)/2),
                                      rep(1, times = length(p1cub)/2)),
                              probability = c(p1cub[, 1], p1cub[, 2],
                                              p2cub[, 1], p2cub[, 2],
                                              p3cub[, 1], p3cub[, 2]),
                              nbr_cub = c(rep("1 cub", times = length(p1cub)),
                                          rep("2 cubs", times = length(p1cub)),
                                          rep("3 cubs", times = length(p1cub)))) %>%
      mutate(nbr_cub = factor(nbr_cub,      # Reordering group factor levels
                              levels = c("1 cub", "2 cubs", "3 cubs")))
    
    color_labels <- c("1 cub", "2 cubs", "3 cubs")
  }
  return(list(df.for.plot, color_labels))
}

