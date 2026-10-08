# Offline historical estimator definitions; extracted without top-level experiment code.
design <- function(data, degree, block_levels = levels(data$block)) {
    data$block <- factor(data$block, levels = block_levels)
    rhs <- if (degree == 1)
        "x + block"
    else "x + I(x^2) + block"
    model.matrix(as.formula(paste("~", rhs)), data, contrasts.arg = list(block = contr.sum(length(block_levels))))
}

aicc <- function(log_likelihood, parameters, observations) {
    -2 * log_likelihood + 2 * parameters + 2 * parameters * (parameters + 1)/(observations - parameters -
        1)
}

fit_student <- function(data, degree, df = 4) {
    block_levels <- levels(data$block)
    X <- design(data, degree, block_levels)
    robust <- rlm(x = X, y = data$y, psi = psi.huber, maxit = 200)
    initial <- coef(robust)
    initial_scale <- max(mad(data$y - drop(X %*% initial)), 0.001)
    objective <- function(parameters) {
        beta <- parameters[seq_len(ncol(X))]
        sigma <- exp(parameters[ncol(X) + 1])
        residual <- (data$y - drop(X %*% beta))/sigma
        -sum(dt(residual, df = df, log = TRUE) - log(sigma))
    }
    optimized <- optim(c(initial, log(initial_scale)), objective, method = "BFGS", control = list(maxit = 3000,
        reltol = 1e-11))
    beta <- optimized$par[seq_len(ncol(X))]
    names(beta) <- colnames(X)
    sigma <- exp(optimized$par[ncol(X) + 1])
    list(beta = beta, sigma = sigma, log_likelihood = -optimized$value, aicc = aicc(-optimized$value,
        ncol(X) + 1, nrow(data)), block_levels = block_levels, degree = degree, df = df, convergence = optimized$convergence)
}

huber_quadratic <- function(data) {
    data$block <- droplevels(data$block)
    unname(coef(rlm(y ~ x + I(x^2) + block, data = data, psi = psi.huber, maxit = 200))["I(x^2)"])
}

resample_blocks <- function(data) {
    blocks <- levels(data$block)
    selected <- sample(blocks, length(blocks), replace = TRUE)
    pieces <- Map(function(old_block, new_block) {
        piece <- data[data$block == old_block, ]
        piece$block <- paste0("boot_", new_block)
        piece
    }, selected, seq_along(selected))
    sampled <- do.call(rbind, pieces)
    sampled$block <- factor(sampled$block)
    rownames(sampled) <- NULL
    sampled
}
