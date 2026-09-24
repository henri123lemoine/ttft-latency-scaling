#!/usr/bin/env Rscript

# The published figures, re-drawn in the layout and palette of the Epoch AI web
# post (square canvas, legend under the title, y-axis title as a panel header,
# model name inside the panel), with one addition: a quadratic fit to the
# fastest request at each context length. Type is Inter, the closest open face
# to the post's Messina Sans. Everything else is read from the released tables.

suppressPackageStartupMessages({
  library(ggplot2)
  library(grid)
})

script_arg <- commandArgs(trailingOnly = FALSE)
script_flag <- grep("^--file=", script_arg, value = TRUE)
script_path <- if (length(script_flag)) {
  normalizePath(sub("^--file=", "", script_flag[[1]]))
} else {
  normalizePath("analysis/figures_floor.R")
}
repo_root <- normalizePath(file.path(dirname(script_path), ".."))
args <- commandArgs(trailingOnly = TRUE)
output_dir <- if (length(args)) normalizePath(args[[1]], mustWork = FALSE) else file.path(repo_root, "figures/floor")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

source(file.path(dirname(script_path), "floor_theme.R"))

# ---------------------------------------------------------------- data ------

four_points <- read.csv(file.path(repo_root, "outputs/tables/request_observations.csv"), check.names = FALSE)
astra_points <- read.csv(file.path(repo_root, "outputs/astra-api/request_observations.csv"), check.names = FALSE)
astra_points$ttft_seconds <- astra_points$y
points <- rbind(
  four_points[, c("model", "total_input_tokens", "ttft_seconds")],
  astra_points[, c("model", "total_input_tokens", "ttft_seconds")]
)

four_fits <- read.csv(file.path(repo_root, "outputs/tables/fit_coefficients.csv"), check.names = FALSE)
astra_fits <- read.csv(file.path(repo_root, "outputs/astra-api/fit_coefficients.csv"), check.names = FALSE)
columns <- c("model", "estimator", "degree", "alpha", "beta", "gamma")
all_fits <- rbind(four_fits[, columns], astra_fits[, columns])

model_order <- c("GPT-5.6 Terra", "GPT-5.6 Sol", "Claude Sonnet 5", "Claude Opus 5", "GPT-6 Astra")
points <- points[points$model %in% model_order, ]

floor_points <- do.call(rbind, lapply(model_order, function(model_name) {
  model_points <- points[points$model == model_name, ]
  per_length <- aggregate(ttft_seconds ~ total_input_tokens, model_points, min)
  per_length$model <- model_name
  per_length
}))

floor_fit <- function(model_name) {
  model_floor <- floor_points[floor_points$model == model_name, ]
  x <- model_floor$total_input_tokens / 1e6
  unname(coef(lm(model_floor$ttft_seconds ~ x + I(x^2))))
}

fit_table <- function(estimator_name, degree, method_name) {
  rows <- all_fits[all_fits$estimator == estimator_name & all_fits$degree == degree, ]
  data.frame(model = rows$model, method = method_name, intercept = rows$alpha, linear = rows$beta, quadratic = rows$gamma)
}
fits <- rbind(
  fit_table("Student-t", 2, "Epoch's Student-t"),
  fit_table("Stochastic frontier", 2, "Epoch's frontier"),
  fit_table("Spike + contention", 2, "Epoch's spike + contention"),
  do.call(rbind, lapply(model_order, function(model_name) {
    coefficient <- floor_fit(model_name)
    data.frame(model = model_name, method = "Floor fit", intercept = coefficient[[1]], linear = coefficient[[2]], quadratic = coefficient[[3]])
  }))
)
student_linear <- fit_table("Student-t", 1, "Epoch's Student-t")

evaluate <- function(coefficient, x_million) {
  coefficient$intercept + coefficient$linear * x_million + coefficient$quadratic * x_million^2
}

curve_rows <- function(model_name, methods) {
  model_points <- points[points$model == model_name, ]
  x_million <- seq(min(model_points$total_input_tokens), max(model_points$total_input_tokens), length.out = 300) / 1e6
  do.call(rbind, lapply(methods, function(method_name) {
    coefficient <- fits[fits$model == model_name & fits$method == method_name, ]
    if (nrow(coefficient) != 1) stop(sprintf("Expected one %s fit for %s", method_name, model_name))
    data.frame(method = method_name, x_thousands = x_million * 1000, ttft_seconds = evaluate(coefficient, x_million))
  }))
}

make_panel <- function(model_name, methods, y_limits, y_breaks, show_floor_points = TRUE) {
  model_points <- points[points$model == model_name, ]
  model_floor <- floor_points[floor_points$model == model_name, ]
  curves <- curve_rows(model_name, methods)
  curves$method <- factor(curves$method, levels = method_style$method)
  colors <- setNames(method_style$color, method_style$method)
  widths <- setNames(method_style$width, method_style$method)

  panel <- ggplot() +
    geom_point(
      data = model_points, aes(x = total_input_tokens / 1000, y = ttft_seconds),
      color = scales::alpha(dot, 0.55), size = 2.9, stroke = 0
    ) +
    geom_line(
      data = curves, aes(x = x_thousands, y = ttft_seconds, color = method, linewidth = method),
      lineend = "round"
    )
  if (show_floor_points) {
    panel <- panel + geom_point(
      data = model_floor, aes(x = total_input_tokens / 1000, y = ttft_seconds),
      color = floor_color, size = 2.2, stroke = 0
    )
  }
  panel +
    annotate("text", x = 40, y = y_limits[[2]] * 0.9, label = model_name, hjust = 0, vjust = 1,
      family = font_family, size = 4.1, color = body_ink) +
    scale_color_manual(values = colors, drop = FALSE) +
    scale_linewidth_manual(values = widths, drop = FALSE) +
    scale_x_continuous(limits = c(0, 950), breaks = c(0, 300, 600, 900), expand = expansion(mult = 0)) +
    scale_y_continuous(limits = y_limits, breaks = y_breaks, expand = expansion(mult = 0)) +
    coord_cartesian(clip = "off") +
    panel_theme
}

raw_entry <- list(kind = "point", color = scales::alpha(dot, 0.8), label = "Raw request")
fastest_entry <- list(kind = "point", color = floor_color, label = "Fastest request")
floor_entry <- list(kind = "line", color = floor_color, label = "Floor fit", lwd = 3)
single_legend <- list(list(kind = "line", color = teal, label = "Epoch's fit"), floor_entry, raw_entry, fastest_entry)
estimator_legend <- list(
  list(kind = "line", color = teal, label = "Student-t"),
  list(kind = "line", color = magenta, label = "Frontier"),
  list(kind = "line", color = orange, label = "Spike + contention"),
  floor_entry, raw_entry, fastest_entry
)
all_methods <- method_style$method

# ------------------------------------------------------------ figure 1 ------

panel_figure(
  "figure_1_headline_with_floor",
  "Fitted to its fastest requests, Claude Opus 5 curves upward\nlike GPT-5.6; Claude Sonnet 5 stays close to linear",
  "",
  single_legend,
  lapply(model_order[1:4], function(m) make_panel(m, c("Epoch's Student-t", "Floor fit"), c(0, 30), c(0, 10, 20, 30))),
  ncol = 2,
  x_label = "Input context (thousand tokens)",
  y_header = "Time to first token (s)",
  caption = "Each dot is one API request. Teal: Epoch's quadratic-capable Student-t fit. Black: quadratic fit to the\nfastest request at each context length."
)

# ------------------------------------------------------------ figure 2 ------

panel_figure(
  "figure_2_gpt_estimators_with_floor",
  "For GPT-5.6, the floor fit lands on top of all three of Epoch's\nestimators",
  "When request-level noise is small, every estimator recovers the same curve.",
  estimator_legend,
  lapply(model_order[1:2], function(m) make_panel(m, all_methods, c(0, 30), c(0, 5, 10, 15, 20, 25, 30))),
  ncol = 2,
  x_label = "Input context (thousand tokens)",
  y_header = "Time to first token (s)",
  caption = ""
)

# ------------------------------------------------------------ figure 3 ------

panel_figure(
  "figure_3_claude_estimators_with_floor",
  "Claude Sonnet 5 is linear under every estimator; Claude Opus 5\nis linear only when its slow requests are averaged in",
  "Epoch's three Opus fits pass through the cloud of slow requests. The floor fit passes\nthrough the fastest ones and curves upward.",
  estimator_legend,
  lapply(model_order[3:4], function(m) make_panel(m, all_methods, c(0, 30), c(0, 5, 10, 15, 20, 25, 30))),
  ncol = 2,
  x_label = "Input context (thousand tokens)",
  y_header = "Time to first token (s)",
  caption = ""
)

# ----------------------------------------------------------- figure A1 ------

panel_figure(
  "figure_a1_astra_with_floor",
  "GPT-6 Astra: Epoch's fit and the floor fit agree",
  "",
  single_legend,
  list(make_panel("GPT-6 Astra", c("Epoch's Student-t", "Floor fit"), c(0, 30), c(0, 10, 20, 30))),
  ncol = 1,
  x_label = "Input context (thousand tokens)",
  y_header = "Time to first token (s)",
  caption = "24 API requests. The two fits are nearly indistinguishable."
)

# ------------------------------------------------------------ figure 4 ------

four_models <- c("Claude Sonnet 5", "GPT-5.6 Terra", "GPT-5.6 Sol", "Claude Opus 5")
primary_degree <- c("GPT-5.6 Terra" = 2, "GPT-5.6 Sol" = 2, "Claude Sonnet 5" = 1, "Claude Opus 5" = 1)
x_million <- seq(1, 10, length.out = 451)
extrapolation <- do.call(rbind, lapply(four_models, function(model_name) {
  epoch_source <- if (primary_degree[[model_name]] == 2) fits[fits$method == "Epoch's Student-t", ] else student_linear
  rbind(
    data.frame(model = model_name, source = "Epoch's fit", x = x_million,
      minutes = evaluate(epoch_source[epoch_source$model == model_name, ], x_million) / 60),
    data.frame(model = model_name, source = "Floor fit", x = x_million,
      minutes = evaluate(fits[fits$method == "Floor fit" & fits$model == model_name, ], x_million) / 60)
  )
}))
extrapolation$model <- factor(extrapolation$model, levels = four_models)
ends <- extrapolation[extrapolation$x == 10, ]
end_labels <- do.call(rbind, lapply(four_models, function(model_name) {
  epoch_end <- ends$minutes[ends$model == model_name & ends$source == "Epoch's fit"]
  floor_end <- ends$minutes[ends$model == model_name & ends$source == "Floor fit"]
  if (abs(epoch_end - floor_end) < 1.5) {
    data.frame(model = model_name, y = (epoch_end + floor_end) / 2,
      label = sprintf("%.1f and %.1f min", epoch_end, floor_end))
  } else {
    data.frame(model = model_name, y = c(epoch_end, floor_end),
      label = c(sprintf("%.1f min (Epoch's fit)", epoch_end), sprintf("%.1f min (floor fit)", floor_end)))
  }
}))
end_labels$model <- factor(end_labels$model, levels = four_models)

extrapolation_panel <- ggplot(extrapolation, aes(x = x, y = minutes, color = model, linetype = source,
  group = interaction(model, source))) +
  geom_line(linewidth = 1.05, lineend = "round") +
  geom_text(data = end_labels, aes(x = 10.15, y = y, label = label, color = model), hjust = 0, vjust = 0.5,
    family = font_family, size = 3.7, inherit.aes = FALSE) +
  scale_color_manual(values = model_colors) +
  scale_linetype_manual(values = c("Epoch's fit" = "22", "Floor fit" = "solid")) +
  scale_x_continuous(breaks = c(1, 3, 5, 7, 9, 11), limits = c(1, 11.9), expand = expansion(mult = 0)) +
  scale_y_continuous(breaks = c(0, 5, 10, 15, 20), limits = c(0, 21), expand = expansion(mult = 0)) +
  coord_cartesian(clip = "off") +
  panel_theme

export_figure("figure_4_extrapolation_with_floor", function() {
  grid.newpage()
  text_grob("Extrapolated from its floor, Claude Opus 5 TTFT rises like\nGPT-5.6 beyond 1 million tokens", 0.08, 0.965, 15.5, face = "bold")
  draw_legend(list(
    list(kind = "line", color = teal, label = "Claude Sonnet 5"),
    list(kind = "line", color = magenta, label = "GPT-5.6 Terra"),
    list(kind = "line", color = orange, label = "GPT-5.6 Sol"),
    list(kind = "line", color = blue, label = "Claude Opus 5")
  ), 0.868)
  draw_legend(list(
    list(kind = "line", color = body_ink, label = "Epoch's fit (quadratic GPT-5.6, linear Claude 5)", lty = "22"),
    list(kind = "line", color = body_ink, label = "Floor fit (quadratic)")
  ), 0.835)
  text_grob("Time to first token (minutes)", 0.08, 0.795, 11, color = body_ink)
  place(extrapolation_panel, 0.08, 0.215, 0.84, 0.55)
  text_grob("Input context (million tokens)", 0.08 + 0.84 * 0.42, 0.20, 11, color = body_ink, just = c("center", "top"))
  draw_footer("Measured data end below 1 million tokens; beyond that, these are stress-test extrapolations, not forecasts.\nDashed: Epoch's fits. Solid: quadratic fits to the fastest request at each length.")
})

# ------------------------------------------------- figure 5: curvature ------
# Two independent intervals for the quadratic coefficient of each model, read
# from outputs/floor/fits.json (written by analysis/floor.py).

curvature <- jsonlite::fromJSON(file.path(repo_root, "outputs/floor/fits.json"), simplifyVector = FALSE)$models
row_order <- c("Claude Sonnet 5", "Claude Opus 5", "GPT-5.6 Terra", "GPT-5.6 Sol", "GPT-6 Astra")
interval_rows <- do.call(rbind, lapply(curvature, function(m) {
  passes <- length(m$per_block_curvature$gammas)
  half <- qt(0.975, passes - 1) * m$per_block_curvature$se
  rbind(
    data.frame(model = m$model, method = "Floor fit", estimate = m$floor_fit$quadratic$gamma,
      low = m$floor_gamma_interval$ci95[[1]], high = m$floor_gamma_interval$ci95[[2]], passes = passes),
    data.frame(model = m$model, method = "One quadratic per pass", estimate = m$per_block_curvature$mean,
      low = m$per_block_curvature$mean - half, high = m$per_block_curvature$mean + half, passes = passes)
  )
}))
interval_rows$label <- sprintf("%s (%d passes)", interval_rows$model, interval_rows$passes)
label_order <- unique(interval_rows$label[match(row_order, interval_rows$model)])
interval_rows$label <- factor(interval_rows$label, levels = rev(label_order))
interval_rows$method <- factor(interval_rows$method, levels = c("Floor fit", "One quadratic per pass"))

curvature_panel <- ggplot(interval_rows, aes(y = label, color = method)) +
  geom_vline(xintercept = 0, color = body_ink, linewidth = 0.5) +
  geom_errorbarh(aes(xmin = low, xmax = high), height = 0, linewidth = 1.1,
    position = position_dodge(width = 0.55), lineend = "round") +
  geom_point(aes(x = estimate), size = 3, position = position_dodge(width = 0.55)) +
  scale_color_manual(values = c("Floor fit" = floor_color, "One quadratic per pass" = teal)) +
  scale_x_continuous(limits = c(-12, 20), breaks = seq(-10, 20, 5), expand = expansion(mult = 0)) +
  panel_theme +
  theme(
    panel.grid.major.y = element_blank(),
    panel.grid.major.x = element_line(color = grid_line, linewidth = 0.5),
    axis.line.x = element_blank(),
    axis.text.y = element_text(size = 11, color = body_ink, hjust = 0, margin = margin(r = 10))
  )

export_figure("figure_5_curvature_intervals", function() {
  grid.newpage()
  text_grob("Only Claude Sonnet 5 has curvature consistent with zero", 0.08, 0.955, 15.5, face = "bold")
  draw_legend(list(
    list(kind = "line", color = floor_color, label = "Floor fit, 95% interval", lwd = 3),
    list(kind = "line", color = teal, label = "One quadratic per chronological pass, mean and 95% interval", lwd = 3)
  ), 0.87)
  place(curvature_panel, 0.08, 0.30, 0.84, 0.53)
  text_grob("Quadratic coefficient of TTFT in context length (seconds per million tokens squared)",
    0.08 + 0.84 * 0.6, 0.275, 11, color = body_ink, just = c("center", "top"))
  draw_footer("The floor fit uses only the fastest request at each length. The per-pass fit uses every request in one\nsweep over all lengths, so slow requests contaminate it; for Opus that widens the interval to cover zero.",
    caption_y = 0.135)
}, width = 8.6, height = 6.6)

write.csv(fits[fits$method == "Floor fit", ], file.path(output_dir, "floor_fit_coefficients.csv"), row.names = FALSE)
cat("Generated floor-overlay figures in", output_dir, "\n")
