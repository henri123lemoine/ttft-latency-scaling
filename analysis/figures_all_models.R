#!/usr/bin/env Rscript

# One panel per shared-prefix session across every model in the repository:
# Epoch's GPT-5.6, Claude 5, GPT-6 Astra and GPT-6/6.1 Sol sessions and the
# Claude 5.5 sessions. Each panel refits Epoch's quadratic Student-t (df = 4,
# sum-contrast block effects) and the quadratic floor fit on the same footing.

script_arg <- commandArgs(trailingOnly = FALSE)
script_flag <- grep("^--file=", script_arg, value = TRUE)
script_path <- if (length(script_flag)) {
  normalizePath(sub("^--file=", "", script_flag[[1]]))
} else {
  normalizePath("analysis/figures_all_models.R")
}
repo_root <- normalizePath(file.path(dirname(script_path), ".."))
args <- commandArgs(trailingOnly = TRUE)
output_dir <- if (length(args)) normalizePath(args[[1]], mustWork = FALSE) else file.path(repo_root, "figures/all-models")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

suppressPackageStartupMessages(library(MASS))
source(file.path(dirname(script_path), "floor_theme.R"))
source(file.path(dirname(script_path), "sol_api_student_helpers.R"))

# ---------------------------------------------------------------- data ------

read_table <- function(...) read.csv(file.path(repo_root, ...), check.names = FALSE)
rows <- function(panel, x, y, block) data.frame(panel = panel, x = x, y = y, block = as.character(block))

headline <- read_table("outputs/tables/request_observations.csv")
astra <- read_table("outputs/astra-api/request_observations.csv")
sol <- read_table("outputs/sol-api/observations.csv")
sol <- sol[sol$used_in_fit, ]
exploratory <- read_table("outputs/exploratory/request_observations.csv")
claude_5_5 <- read_table("outputs/claude-5.5/request_observations.csv")

headline_rows <- function(model, panel) {
  d <- headline[headline$model == model, ]
  rows(panel, d$total_input_tokens / 1e6, d$ttft_seconds, d$block)
}
exploratory_rows <- function(session, panel) {
  d <- exploratory[exploratory$session_id == session, ]
  rows(panel, d$total_input_tokens / 1e6, d$ttft_seconds, d$block)
}
sol_rows <- function(model, panel) {
  d <- sol[sol$model == model, ]
  rows(panel, d$x, d$y, d$block)
}
claude_5_5_rows <- function(model) {
  d <- claude_5_5[claude_5_5$model == model, ]
  rows(model, d$total_input_tokens / 1e6, d$ttft_seconds, d$block)
}

observations <- rbind(
  headline_rows("GPT-5.6 Terra", "GPT-5.6 Terra"),
  headline_rows("GPT-5.6 Sol", "GPT-5.6 Sol"),
  rows("GPT-6 Astra", astra$x, astra$y, astra$block),
  sol_rows("gpt-6-sol", "GPT-6 Sol"),
  sol_rows("gpt-6.1-sol", "GPT-6.1 Sol"),
  headline_rows("Claude Sonnet 5", "Claude Sonnet 5, Aug 14"),
  exploratory_rows("20260813T165440Z-0e5adc75", "Claude Sonnet 5, Aug 13"),
  headline_rows("Claude Opus 5", "Claude Opus 5, Aug 13"),
  exploratory_rows("20260814T134405Z-c4566a73", "Claude Opus 5, Aug 14"),
  claude_5_5_rows("Claude Haiku 5.5"),
  claude_5_5_rows("Claude Sonnet 5.5"),
  claude_5_5_rows("Claude Opus 5.5")
)
panel_order <- unique(observations$panel)

# ---------------------------------------------------------------- fits ------

fit_panel <- function(panel) {
  data <- observations[observations$panel == panel, ]
  data$block <- factor(data$block)
  student <- fit_student(data, 2)
  floor <- aggregate(y ~ x, data, min)
  floor_model <- lm(y ~ x + I(x^2), floor)
  interval <- confint(floor_model)["I(x^2)", ]
  list(
    points = data, floor = floor,
    summary = data.frame(
      panel = panel, passes = nlevels(data$block), requests = nrow(data),
      student_alpha = unname(student$beta["(Intercept)"]), student_beta = unname(student$beta["x"]),
      student_gamma = unname(student$beta["I(x^2)"]),
      student_delta_aicc = fit_student(data, 1)$aicc - student$aicc,
      floor_alpha = unname(coef(floor_model)[1]), floor_beta = unname(coef(floor_model)[2]),
      floor_gamma = unname(coef(floor_model)[3]), floor_gamma_low = interval[[1]], floor_gamma_high = interval[[2]],
      floor_p = summary(floor_model)$coefficients["I(x^2)", "Pr(>|t|)"]
    )
  )
}
fitted <- lapply(panel_order, fit_panel)
names(fitted) <- panel_order
summary_table <- do.call(rbind, lapply(fitted, function(f) f$summary))
write.csv(summary_table, file.path(output_dir, "all_models_fits.csv"), row.names = FALSE)

# -------------------------------------------------------------- figure ------

y_limits <- c(0, 50)
make_panel <- function(panel) {
  f <- fitted[[panel]]
  s <- f$summary
  x <- seq(min(f$points$x), max(f$points$x), length.out = 300)
  curves <- rbind(
    data.frame(method = "Epoch's Student-t", x = x, y = s$student_alpha + s$student_beta * x + s$student_gamma * x^2),
    data.frame(method = "Floor fit", x = x, y = s$floor_alpha + s$floor_beta * x + s$floor_gamma * x^2)
  )
  curves$method <- factor(curves$method, levels = method_style$method)
  note <- sprintf("%d passes. Curvature: %.1f Student-t,\n%.1f floor (%.1f to %.1f)", s$passes, s$student_gamma,
    s$floor_gamma, s$floor_gamma_low, s$floor_gamma_high)
  ggplot() +
    geom_point(data = f$points, aes(x = x * 1000, y = y), color = scales::alpha(dot, 0.55), size = 2.6, stroke = 0) +
    geom_line(data = curves, aes(x = x * 1000, y = y, color = method, linewidth = method), lineend = "round") +
    geom_point(data = f$floor, aes(x = x * 1000, y = y), color = floor_color, size = 2, stroke = 0) +
    annotate("text", x = 40, y = 48, label = panel, hjust = 0, vjust = 1, family = font_family, size = 4.1, color = body_ink) +
    annotate("text", x = 40, y = 42.5, label = note, hjust = 0, vjust = 1, family = font_family, size = 3.1,
      color = muted, lineheight = 1.05) +
    scale_color_manual(values = setNames(method_style$color, method_style$method), drop = FALSE) +
    scale_linewidth_manual(values = setNames(method_style$width, method_style$method), drop = FALSE) +
    scale_x_continuous(limits = c(0, 950), breaks = c(0, 300, 600, 900), expand = expansion(mult = 0)) +
    scale_y_continuous(limits = y_limits, breaks = seq(0, 50, 10), expand = expansion(mult = 0), oob = scales::oob_keep) +
    coord_cartesian(clip = "off") +
    panel_theme
}

ncol <- 3
nrow <- ceiling(length(panel_order) / ncol)
export_figure("figure_all_models_with_floor", function() {
  grid.newpage()
  text_grob("Time to first token against context length, every model measured so far", 0.05, 0.982, 17, face = "bold")
  text_grob("Same shared-prefix protocol throughout. Curvature is the quadratic coefficient in seconds per million tokens squared;\nthe floor fit's 95% interval is in brackets.",
    0.05, 0.958, 11.5, color = muted)
  draw_legend(list(
    list(kind = "line", color = teal, label = "Epoch's Student-t fit"),
    list(kind = "line", color = floor_color, label = "Floor fit", lwd = 3),
    list(kind = "point", color = scales::alpha(dot, 0.8), label = "Raw request"),
    list(kind = "point", color = floor_color, label = "Fastest request")
  ), 0.918, x = 0.05)
  top <- 0.895
  bottom <- 0.085
  gap_x <- 0.035
  gap_y <- 0.03
  width <- (0.90 - gap_x * (ncol - 1)) / ncol
  height <- (top - bottom - gap_y * (nrow - 1)) / nrow
  for (index in seq_along(panel_order)) {
    row <- (index - 1) %/% ncol
    column <- (index - 1) %% ncol
    left <- 0.05 + column * (width + gap_x)
    panel_top <- top - row * (height + gap_y)
    if (column == 0) text_grob("Time to first token (s)", left, panel_top, 10.5, color = body_ink)
    place(make_panel(panel_order[[index]]), left, panel_top - height, width, height - 0.016)
  }
  text_grob("Input context (thousand tokens)", 0.5, bottom - 0.006, 11, color = body_ink, just = c("center", "top"))
  grid.lines(x = unit(c(0.05, 0.95), "npc"), y = unit(c(0.04, 0.04), "npc"), gp = gpar(col = grid_line, lwd = 1))
  text_grob("GPT and Claude 5 data: Epoch AI (CC-BY). Claude 5.5 data: own sessions on Epoch's collector. Fits recomputed identically for every panel.",
    0.05, 0.03, 9.5, color = muted, just = c("left", "top"))
  text_grob("henrilemoine.com", 0.95, 0.03, 9.5, color = muted, just = c("right", "top"))
}, width = 12.6, height = 15.4)

print(format(summary_table[, c("panel", "passes", "student_gamma", "student_delta_aicc", "floor_gamma",
  "floor_gamma_low", "floor_gamma_high", "floor_p")], digits = 3), row.names = FALSE)
