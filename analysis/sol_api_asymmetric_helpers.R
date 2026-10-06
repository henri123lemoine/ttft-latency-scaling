# Offline historical estimator definitions; extracted without top-level experiment code.
make_design <- function(data, degree, block_levels = levels(data$block)) {
    data$block <- factor(data$block, levels = block_levels)
    rhs <- if (degree == 1)
        "x + block"
    else "x + I(x^2) + block"
    model.matrix(as.formula(paste("~", rhs)), data, contrasts.arg = list(block = contr.sum(length(block_levels))))
}

log_exgaussian <- function(residual, sigma, rate) {
    z <- residual/sigma - rate * sigma
    log(rate) - rate * residual + 0.5 * (rate * sigma)^2 + pnorm(z, log.p = TRUE)
}

log_sum_exp2 <- function(a, b) {
    maximum <- pmax(a, b)
    maximum + log(exp(a - maximum) + exp(b - maximum))
}

parameter_bounds <- function(coefficient_names, family, fixed_sigma = NULL) {
    count <- length(coefficient_names)
    lower <- rep(-100, count)
    upper <- rep(100, count)
    names(lower) <- names(upper) <- coefficient_names
    lower["(Intercept)"] <- -50
    upper["(Intercept)"] <- 50
    lower["x"] <- 0
    upper["x"] <- 100
    if ("I(x^2)" %in% coefficient_names) {
        lower["I(x^2)"] <- 0
        upper["I(x^2)"] <- 100
    }
    if (is.null(fixed_sigma)) {
        lower <- c(lower, log_sigma = log(0.02))
        upper <- c(upper, log_sigma = log(20))
    }
    lower <- c(lower, log_rate = log(0.01))
    upper <- c(upper, log_rate = log(20))
    if (family == "spike_exponential") {
        lower <- c(lower, logit_contended = qlogis(0.005))
        upper <- c(upper, logit_contended = qlogis(0.995))
    }
    list(lower = lower, upper = upper)
}

negative_log_likelihood <- function(parameters, X, y, family, fixed_sigma = NULL) {
    coefficient_count <- ncol(X)
    beta <- parameters[seq_len(coefficient_count)]
    if (is.null(fixed_sigma)) {
        sigma <- exp(parameters[coefficient_count + 1])
        rate_index <- coefficient_count + 2
    }
    else {
        sigma <- fixed_sigma
        rate_index <- coefficient_count + 1
    }
    rate <- exp(parameters[rate_index])
    residual <- y - drop(X %*% beta)
    contended <- log_exgaussian(residual, sigma, rate)
    if (family == "frontier_exponential")
        return(-sum(contended))
    probability <- plogis(parameters[rate_index + 1])
    clean <- dnorm(residual, sd = sigma, log = TRUE)
    mixture <- log_sum_exp2(log1p(-probability) + clean, log(probability) + contended)
    -sum(mixture)
}

initial_parameters <- function(X, y, family, contended_probability = 0.35, fixed_sigma = NULL) {
    robust <- tryCatch(rlm(x = X, y = y, psi = psi.huber, maxit = 200), error = function(error) NULL)
    beta <- if (is.null(robust))
        lm.fit(X, y)$coefficients
    else coef(robust)
    beta[!is.finite(beta)] <- 0
    if ("I(x^2)" %in% names(beta))
        beta["I(x^2)"] <- max(0, beta["I(x^2)"])
    beta["x"] <- max(0, beta["x"])
    residual <- y - drop(X %*% beta)
    sigma <- max(0.05, mad(residual, constant = 1.4826), na.rm = TRUE)
    positive_mean <- mean(pmax(residual, 0))
    mean_delay <- max(0.1, positive_mean/max(contended_probability, 0.05))
    parameters <- beta
    if (is.null(fixed_sigma))
        parameters <- c(parameters, log_sigma = log(sigma))
    parameters <- c(parameters, log_rate = log(1/mean_delay))
    if (family == "spike_exponential") {
        parameters <- c(parameters, logit_contended = qlogis(contended_probability))
    }
    parameters
}

estimate_clean_sigma <- function(data) {
    data$block <- droplevels(data$block)
    pilot <- rlm(y ~ x + I(x^2) + block, data = data, psi = psi.huber, maxit = 200, contrasts = list(block = contr.sum(nlevels(data$block))))
    residual <- residuals(pilot)
    lower_side <- residual[residual <= 0]
    estimate <- median(abs(lower_side))/qnorm(0.75)
    max(0.02, estimate)
}

fit_asymmetric <- function(data, family, degree, starts = NULL, fixed_sigma = NULL) {
    block_levels <- levels(data$block)
    X <- make_design(data, degree, block_levels)
    bounds <- parameter_bounds(colnames(X), family, fixed_sigma)
    if (is.null(starts)) {
        probabilities <- if (family == "spike_exponential")
            c(0.1, 0.35, 0.7, 0.9)
        else 0.35
        starts <- lapply(probabilities, function(probability) {
            initial_parameters(X, data$y, family, probability, fixed_sigma)
        })
    }
    fits <- lapply(starts, function(start) {
        start <- pmax(bounds$lower + 1e-08, pmin(bounds$upper - 1e-08, start))
        tryCatch(optim(start, negative_log_likelihood, X = X, y = data$y, family = family, fixed_sigma = fixed_sigma,
            method = "L-BFGS-B", lower = bounds$lower, upper = bounds$upper, control = list(maxit = 3000,
                factr = 1e+07, pgtol = 1e-08)), error = function(error) NULL)
    })
    fits <- Filter(function(fit) !is.null(fit) && is.finite(fit$value), fits)
    if (!length(fits))
        stop("All optimizations failed")
    fit <- fits[[which.min(vapply(fits, function(candidate) candidate$value, numeric(1)))]]
    coefficient_count <- ncol(X)
    beta <- fit$par[seq_len(coefficient_count)]
    names(beta) <- colnames(X)
    if (is.null(fixed_sigma)) {
        sigma <- exp(fit$par[coefficient_count + 1])
        rate_index <- coefficient_count + 2
    }
    else {
        sigma <- fixed_sigma
        rate_index <- coefficient_count + 1
    }
    rate <- exp(fit$par[rate_index])
    probability <- if (family == "spike_exponential") {
        plogis(fit$par[rate_index + 1])
    }
    else {
        1
    }
    parameter_count <- length(fit$par)
    observations <- nrow(data)
    aicc <- 2 * fit$value + 2 * parameter_count + 2 * parameter_count * (parameter_count + 1)/(observations -
        parameter_count - 1)
    tolerance <- 1e-04
    at_boundary <- any(abs(fit$par - bounds$lower) < tolerance | abs(fit$par - bounds$upper) < tolerance)
    list(family = family, degree = degree, beta = beta, sigma = sigma, rate = rate, probability = probability,
        fixed_sigma = fixed_sigma, nll = fit$value, aicc = aicc, convergence = fit$convergence, at_boundary = at_boundary,
        parameters = fit$par, block_levels = block_levels)
}

resample_blocks <- function(data) {
    block_levels <- levels(data$block)
    selected <- sample(block_levels, length(block_levels), replace = TRUE)
    pieces <- Map(function(old, new) {
        piece <- data[data$block == old, ]
        piece$block <- paste0("boot_", new)
        piece
    }, selected, seq_along(selected))
    sampled <- do.call(rbind, pieces)
    sampled$block <- factor(sampled$block)
    rownames(sampled) <- NULL
    sampled
}
