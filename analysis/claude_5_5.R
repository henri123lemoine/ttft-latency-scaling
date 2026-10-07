#!/usr/bin/env Rscript

# Epoch's Student-t (df = 4) linear and quadratic fits with sum-contrast block
# effects, as in analysis/reproduce.R, for the Claude 5.5 shared-prefix sessions.
# Adds a whole-block bootstrap of the quadratic Huber refit and a floor figure.

suppressPackageStartupMessages({
  library(jsonlite)
  library(MASS)
  library(ggplot2)
})

set.seed(20261007)
bootstrap_count <- as.integer(Sys.getenv("CLAUDE_5_5_BOOTSTRAP", "2000"))
dir.create("outputs/claude-5.5", recursive = TRUE, showWarnings = FALSE)
dir.create("figures", showWarnings = FALSE)

model_names <- c(
  "claude-haiku-5-5" = "Claude Haiku 5.5",
  "claude-sonnet-5-5" = "Claude Sonnet 5.5",
  "claude-opus-5-5" = "Claude Opus 5.5"
)

read_run <- function(path) {
  session <- fromJSON(readLines(path, n = 1), simplifyVector = TRUE)
  if (!grepl("shared-prefix$", session$label)) return(NULL)
  records <- stream_in(file(path), verbose = FALSE)
  keep <- records$type == "sample" & records$kind == "measured" & records$valid
  records <- records[keep, ]
  data.frame(
    model = unname(model_names[records$model]),
    x = records$target_tokens / 1e6,
    ttft = records$ttft_ns / 1e9,
    first_content = records$first_content_ns / 1e9,
    block = factor(records$repetition + 1)
  )
}

design_matrix <- function(data, degree, block_levels = levels(data$block)) {
  data$block <- factor(data$block, levels = block_levels)
  rhs <- if (degree == 1) "x + block" else "x + I(x^2) + block"
  model.matrix(
    as.formula(paste("~", rhs)),
    data,
    contrasts.arg = list(block = contr.sum(length(block_levels)))
  )
}

aicc <- function(log_likelihood, parameter_count, observation_count) {
  -2 * log_likelihood + 2 * parameter_count +
    2 * parameter_count * (parameter_count + 1) /
      (observation_count - parameter_count - 1)
}

fit_student_t <- function(data, degree, df = 4) {
  X <- design_matrix(data, degree)
  initial_fit <- rlm(x = X, y = data$y, psi = psi.huber, maxit = 200)
  initial <- coef(initial_fit)
  initial_scale <- max(mad(data$y - drop(X %*% initial)), 1e-3)
  objective <- function(parameters) {
    beta <- parameters[seq_len(ncol(X))]
    sigma <- exp(parameters[ncol(X) + 1])
    residual <- (data$y - drop(X %*% beta)) / sigma
    -sum(dt(residual, df = df, log = TRUE) - log(sigma))
  }
  optimized <- optim(
    c(initial, log(initial_scale)), objective,
    method = "BFGS", control = list(maxit = 2000, reltol = 1e-10)
  )
  beta <- optimized$par[seq_len(ncol(X))]
  names(beta) <- colnames(X)
  list(
    beta = beta,
    sigma = exp(optimized$par[ncol(X) + 1]),
    aicc = aicc(-optimized$value, ncol(X) + 1, nrow(data)),
    convergence = optimized$convergence
  )
}

huber_gamma <- function(data) {
  data$block <- droplevels(data$block)
  fit <- rlm(
    y ~ x + I(x^2) + block, data = data, psi = psi.huber, maxit = 200,
    contrasts = list(block = contr.sum(nlevels(data$block)))
  )
  unname(coef(fit)["I(x^2)"])
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
  sampled
}

runs <- Filter(Negate(is.null), lapply(
  sort(list.files("data/raw/claude-5.5", pattern = "\\.jsonl$", full.names = TRUE)),
  read_run
))
observations <- do.call(rbind, runs)
observations$model <- factor(observations$model, levels = unname(model_names))

rows <- list()
observations$model <- droplevels(observations$model)
for (model_name in levels(observations$model)) {
  for (timer in c("ttft", "first_content")) {
    data <- observations[observations$model == model_name, ]
    data$block <- droplevels(data$block)
    data$y <- data[[timer]]
    linear <- fit_student_t(data, 1)
    quadratic <- fit_student_t(data, 2)
    gammas <- vapply(seq_len(bootstrap_count), function(i) {
      tryCatch(huber_gamma(resample_blocks(data)), error = function(e) NA_real_)
    }, numeric(1))
    gammas <- gammas[is.finite(gammas)]
    interval <- quantile(gammas, c(0.025, 0.5, 0.975), names = FALSE)
    rows[[length(rows) + 1]] <- data.frame(
      model = model_name,
      timer = timer,
      blocks = nlevels(data$block),
      observations = nrow(data),
      linear_alpha = unname(linear$beta["(Intercept)"]),
      linear_beta = unname(linear$beta["x"]),
      quadratic_alpha = unname(quadratic$beta["(Intercept)"]),
      quadratic_beta = unname(quadratic$beta["x"]),
      student_t_gamma = unname(quadratic$beta["I(x^2)"]),
      delta_aicc_linear_minus_quadratic = linear$aicc - quadratic$aicc,
      huber_bootstrap_gamma_q025 = interval[1],
      huber_bootstrap_gamma_median = interval[2],
      huber_bootstrap_gamma_q975 = interval[3],
      huber_bootstrap_fraction_gamma_positive = mean(gammas > 0),
      convergence = max(linear$convergence, quadratic$convergence)
    )
  }
}
table <- do.call(rbind, rows)
write.csv(table, "outputs/claude-5.5/student_t_fits.csv", row.names = FALSE)
print(format(table, digits = 3), row.names = FALSE)

observations$fast <- with(observations, ttft < 0.6 * ave(ttft, model, x, FUN = median))
floor <- aggregate(ttft ~ model + x, observations[!observations$fast, ], min)
curve <- do.call(rbind, lapply(split(floor, floor$model, drop = TRUE), function(d) {
  grid <- data.frame(x = seq(0.05, 0.9, length.out = 100))
  rbind(
    data.frame(model = d$model[1], x = grid$x, fit = "linear",
               ttft = predict(lm(ttft ~ x, d), grid)),
    data.frame(model = d$model[1], x = grid$x, fit = "quadratic",
               ttft = predict(lm(ttft ~ x + I(x^2), d), grid))
  )
}))
plot <- ggplot(observations[!observations$fast, ], aes(x * 1000, ttft)) +
  geom_point(alpha = 0.35, size = 1.2, colour = "grey35") +
  geom_line(data = curve, aes(linetype = fit), colour = "#b5442e", linewidth = 0.6) +
  geom_point(data = floor, colour = "#b5442e", size = 2) +
  geom_point(data = observations[observations$fast, ], shape = 1, size = 2.2, colour = "#2a6f97") +
  facet_wrap(~model, scales = "free_y") +
  scale_linetype_manual(values = c(linear = "dashed", quadratic = "solid"), name = "Floor fit") +
  labs(
    x = "Input tokens (thousands)", y = "Time to first token (s)",
    title = "Claude 5.5 TTFT by context length, 2026-10-07",
    subtitle = paste(
      "Grey: every request. Red: fastest request at each length, with linear and quadratic fits.",
      "Blue rings: requests under 60% of their length's median, left out of the floor.", sep = "\n"
    )
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom", panel.grid.minor = element_blank())
ggsave("figures/claude-5.5-floor.png", plot, width = 11, height = 4.4, dpi = 160)
