#!/usr/bin/env Rscript

# Figures for the Claude 5.5 sessions, in the layout of the floor-fit post.
# Reads outputs/claude-5.5/ (analysis/claude_5_5.py and analysis/claude_5_5.R)
# and outputs/floor/update.json for the Claude 5 reference intervals.

script_arg <- commandArgs(trailingOnly = FALSE)
script_flag <- grep("^--file=", script_arg, value = TRUE)
script_path <- if (length(script_flag)) {
  normalizePath(sub("^--file=", "", script_flag[[1]]))
} else {
  normalizePath("analysis/figures_claude_5_5.R")
}
repo_root <- normalizePath(file.path(dirname(script_path), ".."))
args <- commandArgs(trailingOnly = TRUE)
output_dir <- if (length(args)) normalizePath(args[[1]], mustWork = FALSE) else file.path(repo_root, "figures/claude-5.5")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

source(file.path(dirname(script_path), "floor_theme.R"))

draw_footer <- function(caption, caption_y = 0.085) {
  if (nzchar(caption)) text_grob(caption, 0.08, caption_y, 10, color = muted)
  grid.lines(x = unit(c(0.08, 0.92), "npc"), y = unit(c(0.045, 0.045), "npc"), gp = gpar(col = grid_line, lwd = 1))
  text_grob("Data: own sessions, 2026-10-07, on Epoch AI's protocol and collector.", 0.08, 0.03, 9.5, color = muted, just = c("left", "top"))
  text_grob("henrilemoine.com", 0.92, 0.03, 9.5, color = muted, just = c("right", "top"))
}

# ---------------------------------------------------------------- data ------

model_order <- c("Claude Haiku 5.5", "Claude Sonnet 5.5", "Claude Opus 5.5")
model_colors <- c("Claude Haiku 5.5" = magenta, "Claude Sonnet 5.5" = teal, "Claude Opus 5.5" = blue)
points <- read.csv(file.path(repo_root, "outputs/claude-5.5/request_observations.csv"), check.names = FALSE)
student <- read.csv(file.path(repo_root, "outputs/claude-5.5/student_t_fits.csv"), check.names = FALSE)
student <- student[student$timer == "ttft", ]
sessions <- jsonlite::fromJSON(file.path(repo_root, "outputs/claude-5.5/fits.json"), simplifyVector = FALSE)$sessions
names(sessions) <- vapply(sessions, function(s) s$model, character(1))

floor_points <- do.call(rbind, lapply(model_order, function(model_name) {
  per_length <- aggregate(ttft_seconds ~ target_tokens, points[points$model == model_name, ], min)
  per_length$model <- model_name
  per_length
}))

coefficient_row <- function(model_name, method, alpha, beta, gamma) {
  data.frame(model = model_name, method = method, intercept = alpha, linear = beta, quadratic = gamma)
}
fits <- do.call(rbind, lapply(model_order, function(model_name) {
  s <- student[student$model == model_name, ]
  q <- sessions[[model_name]]$fits$ttft$floor_fit$quadratic
  rbind(
    coefficient_row(model_name, "Epoch's Student-t", s$quadratic_alpha, s$quadratic_beta, s$student_t_gamma),
    coefficient_row(model_name, "Student-t linear", s$linear_alpha, s$linear_beta, 0),
    coefficient_row(model_name, "Floor fit", q$alpha, q$beta, q$gamma)
  )
}))
primary_degree <- setNames(ifelse(student$delta_aicc_linear_minus_quadratic > 0, 2, 1), student$model)

evaluate <- function(coefficient, x_million) {
  coefficient$intercept + coefficient$linear * x_million + coefficient$quadratic * x_million^2
}

curve_rows <- function(model_name, methods) {
  x_million <- seq(0.05, 0.9, length.out = 300)
  do.call(rbind, lapply(methods, function(method_name) {
    coefficient <- fits[fits$model == model_name & fits$method == method_name, ]
    data.frame(model = model_name, method = method_name, x_thousands = x_million * 1000,
      ttft_seconds = evaluate(coefficient, x_million))
  }))
}

# ------------------------------------------------------------ figure 1 ------

make_panel <- function(model_name, y_limits, y_breaks) {
  model_points <- points[points$model == model_name, ]
  model_floor <- floor_points[floor_points$model == model_name, ]
  curves <- curve_rows(model_name, c("Epoch's Student-t", "Floor fit"))
  curves$method <- factor(curves$method, levels = method_style$method)
  ggplot() +
    geom_point(data = model_points, aes(x = target_tokens / 1000, y = ttft_seconds),
      color = scales::alpha(dot, 0.55), size = 2.9, stroke = 0) +
    geom_line(data = curves, aes(x = x_thousands, y = ttft_seconds, color = method, linewidth = method), lineend = "round") +
    geom_point(data = model_floor, aes(x = target_tokens / 1000, y = ttft_seconds), color = floor_color, size = 2.2, stroke = 0) +
    annotate("text", x = 40, y = y_limits[[2]] * 0.9, label = sprintf("%s (%d passes)", model_name, sessions[[model_name]]$blocks),
      hjust = 0, vjust = 1, family = font_family, size = 4.1, color = body_ink) +
    scale_color_manual(values = setNames(method_style$color, method_style$method), drop = FALSE) +
    scale_linewidth_manual(values = setNames(method_style$width, method_style$method), drop = FALSE) +
    scale_x_continuous(limits = c(0, 950), breaks = c(0, 300, 600, 900), expand = expansion(mult = 0)) +
    scale_y_continuous(limits = y_limits, breaks = y_breaks, expand = expansion(mult = 0)) +
    coord_cartesian(clip = "off") +
    panel_theme
}

floors_panel <- local({
  curves <- do.call(rbind, lapply(model_order, function(m) curve_rows(m, "Floor fit")))
  labels <- data.frame(model = model_order, y = c(44.5, 40, 35.5))
  ggplot() +
    geom_line(data = curves, aes(x = x_thousands, y = ttft_seconds, color = model), linewidth = 1.1, lineend = "round") +
    geom_point(data = floor_points, aes(x = target_tokens / 1000, y = ttft_seconds, color = model), size = 2.2, stroke = 0) +
    geom_text(data = labels, aes(x = 40, y = y, label = model, color = model), hjust = 0, vjust = 1,
      family = font_family, size = 4.1) +
    scale_color_manual(values = model_colors) +
    scale_x_continuous(limits = c(0, 950), breaks = c(0, 300, 600, 900), expand = expansion(mult = 0)) +
    scale_y_continuous(limits = c(0, 50), breaks = c(0, 10, 20, 30, 40, 50), expand = expansion(mult = 0)) +
    coord_cartesian(clip = "off") +
    panel_theme
})

panel_figure(
  "figure_1_claude_5_5_with_floor",
  "Claude Haiku 5.5 curves upward under both fits; Sonnet 5.5 and\nOpus 5.5 have floors too ragged to call",
  "",
  list(
    list(kind = "line", color = teal, label = "Epoch's fit"),
    list(kind = "line", color = floor_color, label = "Floor fit", lwd = 3),
    list(kind = "point", color = scales::alpha(dot, 0.8), label = "Raw request"),
    list(kind = "point", color = floor_color, label = "Fastest request")
  ),
  list(
    make_panel("Claude Haiku 5.5", c(0, 50), c(0, 10, 20, 30, 40, 50)),
    make_panel("Claude Sonnet 5.5", c(0, 50), c(0, 10, 20, 30, 40, 50)),
    make_panel("Claude Opus 5.5", c(0, 50), c(0, 10, 20, 30, 40, 50)),
    floors_panel
  ),
  ncol = 2,
  x_label = "Input context (thousand tokens)",
  y_header = "Time to first token (s)",
  caption = "Each dot is one API request. Teal: Epoch's quadratic-capable Student-t fit. Black: quadratic fit to the\nfastest request at each context length. Bottom right: the three floors and their fits together."
)

# ------------------------------------------------- figure 2: curvature ------

reference <- jsonlite::fromJSON(file.path(repo_root, "outputs/floor/update.json"), simplifyVector = FALSE)$models
interval_rows <- rbind(
  do.call(rbind, lapply(model_order, function(model_name) {
    fit <- sessions[[model_name]]$fits$ttft
    passes <- sessions[[model_name]]$blocks
    half <- qt(0.975, passes - 1) * fit$per_block_curvature$se
    label <- sprintf("%s (%d passes)", model_name, passes)
    rbind(
      data.frame(label = label, method = "Floor fit", estimate = fit$floor_fit$quadratic$gamma,
        low = fit$floor_gamma_interval$ci95[[1]], high = fit$floor_gamma_interval$ci95[[2]]),
      data.frame(label = label, method = "One quadratic per pass", estimate = fit$per_block_curvature$mean,
        low = fit$per_block_curvature$mean - half, high = fit$per_block_curvature$mean + half)
    )
  })),
  do.call(rbind, lapply(reference, function(m) do.call(rbind, lapply(c("headline", "exploratory"), function(key) {
    s <- m[[key]]
    data.frame(label = sprintf("%s, %s (%d passes)", m$model, format(as.Date(s$date), "%b %d"), s$blocks),
      method = "Claude 5 floor fit, from the post", estimate = s$fit$gamma, low = s$fit$gamma_ci95[[1]], high = s$fit$gamma_ci95[[2]])
  }))))
)
interval_rows$label <- factor(interval_rows$label, levels = rev(unique(interval_rows$label)))
interval_rows$method <- factor(interval_rows$method, levels = c("Floor fit", "One quadratic per pass", "Claude 5 floor fit, from the post"))

curvature_panel <- ggplot(interval_rows, aes(y = label, color = method)) +
  geom_vline(xintercept = 0, color = body_ink, linewidth = 0.5) +
  geom_errorbarh(aes(xmin = low, xmax = high), height = 0, linewidth = 1.1,
    position = position_dodge(width = 0.55), lineend = "round") +
  geom_point(aes(x = estimate), size = 3, position = position_dodge(width = 0.55)) +
  scale_color_manual(values = c("Floor fit" = floor_color, "One quadratic per pass" = teal, "Claude 5 floor fit, from the post" = muted)) +
  scale_x_continuous(limits = c(-60, 70), breaks = seq(-60, 60, 20), expand = expansion(mult = 0)) +
  panel_theme +
  theme(
    panel.grid.major.y = element_blank(),
    panel.grid.major.x = element_line(color = grid_line, linewidth = 0.5),
    axis.line.x = element_blank(),
    axis.text.y = element_text(size = 10.5, color = body_ink, hjust = 0, margin = margin(r = 10))
  )

export_figure("figure_2_claude_5_5_curvature", function() {
  grid.newpage()
  text_grob("Only Claude Haiku 5.5's curvature excludes zero", 0.08, 0.955, 15.5, face = "bold")
  draw_legend(list(
    list(kind = "line", color = floor_color, label = "Floor fit, 95% interval", lwd = 3),
    list(kind = "line", color = teal, label = "One quadratic per pass", lwd = 3),
    list(kind = "line", color = muted, label = "Claude 5 floor fit, from the post", lwd = 3)
  ), 0.87)
  place(curvature_panel, 0.08, 0.30, 0.84, 0.53)
  text_grob("Quadratic coefficient of TTFT in context length (seconds per million tokens squared)",
    0.08 + 0.84 * 0.6, 0.275, 11, color = body_ink, just = c("center", "top"))
  draw_footer("The floor fit uses only the fastest request at each length. At nine or ten passes, a few unusually fast\nrequests still set the floor at some lengths and not others, which widens the Sonnet 5.5 and Opus 5.5 intervals.",
    caption_y = 0.135)
}, width = 8.6, height = 6.6)

# --------------------------------------------- figure 3: extrapolation ------

x_million <- seq(1, 10, length.out = 451)
extrapolation <- do.call(rbind, lapply(model_order, function(model_name) {
  epoch_method <- if (primary_degree[[model_name]] == 2) "Epoch's Student-t" else "Student-t linear"
  rows <- data.frame(model = model_name, source = "Epoch's fit", x = x_million,
    minutes = evaluate(fits[fits$model == model_name & fits$method == epoch_method, ], x_million) / 60)
  floor_interval <- sessions[[model_name]]$fits$ttft$floor_gamma_interval$ci95
  if (floor_interval[[1]] > 0) {
    rows <- rbind(rows, data.frame(model = model_name, source = "Floor fit", x = x_million,
      minutes = evaluate(fits[fits$model == model_name & fits$method == "Floor fit", ], x_million) / 60))
  }
  rows
}))
extrapolation$model <- factor(extrapolation$model, levels = model_order)
ends <- extrapolation[extrapolation$x == 10, ]
ends$label <- sprintf("%.1f min (%s)", ends$minutes, ifelse(ends$source == "Floor fit", "floor fit", "Epoch's fit"))

extrapolation_panel <- ggplot(extrapolation, aes(x = x, y = minutes, color = model, linetype = source,
  group = interaction(model, source))) +
  geom_line(linewidth = 1.05, lineend = "round") +
  geom_text(data = ends, aes(x = 10.15, y = minutes, label = label, color = model), hjust = 0, vjust = 0.5,
    family = font_family, size = 3.7, inherit.aes = FALSE) +
  scale_color_manual(values = model_colors) +
  scale_linetype_manual(values = c("Epoch's fit" = "22", "Floor fit" = "solid")) +
  scale_x_continuous(breaks = c(1, 3, 5, 7, 9, 11), limits = c(1, 11.9), expand = expansion(mult = 0)) +
  scale_y_continuous(breaks = c(0, 10, 20, 30), limits = c(0, 31), expand = expansion(mult = 0)) +
  coord_cartesian(clip = "off") +
  panel_theme

export_figure("figure_3_claude_5_5_extrapolation", function() {
  grid.newpage()
  text_grob("Extrapolated to 10 million tokens, Claude Haiku 5.5 takes\nlonger to start than Sonnet 5.5 or Opus 5.5 under Epoch's fits", 0.08, 0.965, 15.5, face = "bold")
  draw_legend(list(
    list(kind = "line", color = magenta, label = "Claude Haiku 5.5"),
    list(kind = "line", color = teal, label = "Claude Sonnet 5.5"),
    list(kind = "line", color = blue, label = "Claude Opus 5.5")
  ), 0.868)
  draw_legend(list(
    list(kind = "line", color = body_ink, label = "Epoch's fit (quadratic Haiku, linear Sonnet and Opus)", lty = "22"),
    list(kind = "line", color = body_ink, label = "Floor fit (quadratic)")
  ), 0.835)
  text_grob("Time to first token (minutes)", 0.08, 0.795, 11, color = body_ink)
  place(extrapolation_panel, 0.08, 0.215, 0.84, 0.55)
  text_grob("Input context (million tokens)", 0.08 + 0.84 * 0.42, 0.20, 11, color = body_ink, just = c("center", "top"))
  draw_footer("Measured data end below 1 million tokens; beyond that, these are stress-test extrapolations, not forecasts.\nFloor fits are drawn only where the floor's curvature interval excludes zero, which leaves Haiku 5.5.")
})

cat("Generated Claude 5.5 figures in", output_dir, "\n")
