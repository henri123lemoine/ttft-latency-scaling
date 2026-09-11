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

font_dir <- normalizePath(file.path(repo_root, "assets/fonts/Inter"))
font_config <- tempfile(fileext = ".conf")
font_cache <- tempfile(pattern = "fontconfig-cache-")
dir.create(font_cache)
writeLines(c(
  "<?xml version=\"1.0\"?>",
  "<!DOCTYPE fontconfig SYSTEM \"fonts.dtd\">",
  "<fontconfig>",
  "  <include ignore_missing=\"yes\">/etc/fonts/fonts.conf</include>",
  sprintf("  <dir>%s</dir>", font_dir),
  sprintf("  <cachedir>%s</cachedir>", font_cache),
  "</fontconfig>"
), font_config)
Sys.setenv(FONTCONFIG_FILE = font_config)
on.exit(unlink(c(font_config, font_cache), recursive = TRUE), add = TRUE)
font_family <- "Inter"

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

# --------------------------------------------------------------- style ------

ink <- "#090c0c"
body_ink <- "#212a2a"
muted <- "#6c8080"
grid_line <- "#e0e4e4"
dot <- "#b0bcbc"
teal <- "#00a0a0"
magenta <- "#e03890"
orange <- "#f86038"
blue <- "#0058d8"
floor_color <- ink

method_style <- data.frame(
  method = c("Epoch's Student-t", "Epoch's frontier", "Epoch's spike + contention", "Floor fit"),
  color = c(teal, magenta, orange, floor_color),
  width = c(1.0, 1.0, 1.0, 1.25),
  stringsAsFactors = FALSE
)
model_colors <- c("Claude Sonnet 5" = teal, "GPT-5.6 Terra" = magenta, "GPT-5.6 Sol" = orange, "Claude Opus 5" = blue)

panel_theme <- theme_minimal(base_size = 11, base_family = font_family) +
  theme(
    plot.background = element_rect(fill = "white", color = NA),
    panel.background = element_rect(fill = "white", color = NA),
    panel.grid.major.y = element_line(color = grid_line, linewidth = 0.5),
    panel.grid.major.x = element_blank(),
    panel.grid.minor = element_blank(),
    axis.line.x = element_line(color = body_ink, linewidth = 0.45),
    axis.ticks = element_blank(),
    axis.text = element_text(size = 10, color = muted),
    axis.text.y = element_text(hjust = 1, margin = margin(r = 6)),
    axis.text.x = element_text(margin = margin(t = 5)),
    axis.title = element_blank(),
    legend.position = "none",
    plot.margin = margin(4, 8, 2, 2, unit = "pt")
  )

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

text_grob <- function(label, x, y, size, color = ink, face = "plain", just = c("left", "top"), lineheight = 1.15) {
  grid.text(label, x = unit(x, "npc"), y = unit(y, "npc"), just = just,
    gp = gpar(fontfamily = font_family, fontsize = size, col = color, fontface = face, lineheight = lineheight))
}

draw_legend <- function(entries, y, x = 0.08, size = 11) {
  if (length(entries) > 4) size <- 10.3
  cursor <- x
  for (entry in entries) {
    if (identical(entry$kind, "point")) {
      grid.points(x = unit(cursor + 0.008, "npc"), y = unit(y, "npc"), pch = 16, size = unit(7, "pt"),
        gp = gpar(col = entry$color))
      cursor <- cursor + 0.02
    } else {
      grid.lines(x = unit(c(cursor, cursor + 0.022), "npc"), y = unit(c(y, y), "npc"),
        gp = gpar(col = entry$color, lwd = if (is.null(entry$lwd)) 2.4 else entry$lwd,
          lty = if (is.null(entry$lty)) 1 else entry$lty, lineend = "round"))
      cursor <- cursor + 0.03
    }
    width <- convertWidth(grobWidth(textGrob(entry$label, gp = gpar(fontfamily = font_family, fontsize = size))), "npc", valueOnly = TRUE)
    text_grob(entry$label, cursor, y, size, color = body_ink, just = c("left", "center"))
    cursor <- cursor + width + 0.03
  }
}

draw_footer <- function(caption) {
  if (nzchar(caption)) text_grob(caption, 0.08, 0.085, 10, color = muted)
  grid.lines(x = unit(c(0.08, 0.92), "npc"), y = unit(c(0.045, 0.045), "npc"), gp = gpar(col = grid_line, lwd = 1))
  text_grob("Data and fits: Epoch AI (CC-BY). Floor fit added.", 0.08, 0.03, 9.5, color = muted, just = c("left", "top"))
  text_grob("henrilemoine.com", 0.92, 0.03, 9.5, color = muted, just = c("right", "top"))
}

place <- function(plot, left, bottom, width, height) {
  print(plot, vp = viewport(x = unit(left, "npc"), y = unit(bottom, "npc"), width = unit(width, "npc"),
    height = unit(height, "npc"), just = c("left", "bottom")))
}

export_figure <- function(stem, draw, width = 8.6, height = 8.96) {
  path_for <- function(ext) file.path(output_dir, paste0(stem, ".", ext))
  png(filename = path_for("png"), width = width, height = height, units = "in", res = 150, bg = "white", type = "cairo")
  draw()
  dev.off()
  svg(filename = path_for("svg"), width = width, height = height, bg = "white", pointsize = 12, family = font_family)
  draw()
  dev.off()
}

# A figure made of panels on a common grid, in the layout of the web post.
panel_figure <- function(stem, title, subtitle, legend, panels, ncol, x_label, y_header, caption) {
  nrow <- ceiling(length(panels) / ncol)
  export_figure(stem, function() {
    grid.newpage()
    top <- 0.965
    text_grob(title, 0.08, top, 15.5, face = "bold")
    title_lines <- length(strsplit(title, "\n")[[1]])
    top <- top - 0.033 * title_lines - 0.012
    if (nzchar(subtitle)) {
      text_grob(subtitle, 0.08, top, 11.5, color = muted)
      top <- top - 0.026 * length(strsplit(subtitle, "\n")[[1]]) - 0.012
    }
    draw_legend(legend, top - 0.008)
    top <- top - 0.045
    bottom <- if (nzchar(caption)) 0.16 else 0.13
    gap_x <- 0.045
    gap_y <- 0.085
    width <- (0.84 - gap_x * (ncol - 1)) / ncol
    height <- (top - bottom - gap_y * (nrow - 1)) / nrow
    for (index in seq_along(panels)) {
      row <- (index - 1) %/% ncol
      column <- (index - 1) %% ncol
      left <- 0.08 + column * (width + gap_x)
      panel_top <- top - row * (height + gap_y)
      text_grob(y_header, left, panel_top, 11, color = body_ink)
      place(panels[[index]], left, panel_top - height, width, height - 0.03)
      if (row == nrow - 1 || index + ncol > length(panels)) {
        text_grob(x_label, left + width / 2 + 0.02, panel_top - height - 0.012, 11, color = body_ink, just = c("center", "top"))
      }
    }
    draw_footer(caption)
  })
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

write.csv(fits[fits$method == "Floor fit", ], file.path(output_dir, "floor_fit_coefficients.csv"), row.names = FALSE)
cat("Generated floor-overlay figures in", output_dir, "\n")
