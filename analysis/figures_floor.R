#!/usr/bin/env Rscript

# The released figures, re-rendered with one addition: a quadratic fit to the
# fastest request at each context length (the "floor"). Theme, palette, panel
# layout, scales, and fonts follow analysis/figures.R so the two sets of figures
# can be compared directly.

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
output_dir <- if (length(args)) {
  normalizePath(args[[1]], mustWork = FALSE)
} else {
  file.path(repo_root, "figures/floor")
}
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

four_points <- read.csv(file.path(repo_root, "outputs/tables/request_observations.csv"),
  check.names = FALSE)
astra_points <- read.csv(file.path(repo_root, "outputs/astra-api/request_observations.csv"),
  check.names = FALSE)
astra_points$ttft_seconds <- astra_points$y
points <- rbind(
  four_points[, c("model", "total_input_tokens", "ttft_seconds")],
  astra_points[, c("model", "total_input_tokens", "ttft_seconds")]
)
points$model_label <- points$model

four_fits <- read.csv(file.path(repo_root, "outputs/tables/fit_coefficients.csv"),
  check.names = FALSE)
astra_fits <- read.csv(file.path(repo_root, "outputs/astra-api/fit_coefficients.csv"),
  check.names = FALSE)
columns <- c("model", "estimator", "degree", "alpha", "beta", "gamma")
all_fits <- rbind(four_fits[, columns], astra_fits[, columns])

model_order <- c("GPT-5.6 Terra", "GPT-5.6 Sol", "Claude Sonnet 5", "Claude Opus 5", "GPT-6 Astra")
points <- points[points$model_label %in% model_order, ]
points$model_label <- factor(points$model_label, levels = model_order)

floor_points <- do.call(rbind, lapply(split(points, points$model_label), function(model_points) {
  per_length <- aggregate(ttft_seconds ~ total_input_tokens, model_points, min)
  per_length$model_label <- model_points$model_label[[1]]
  per_length
}))
floor_points$model_label <- factor(floor_points$model_label, levels = model_order)

floor_fit <- function(model_name) {
  model_floor <- floor_points[floor_points$model_label == model_name, ]
  x <- model_floor$total_input_tokens / 1e6
  fit <- lm(model_floor$ttft_seconds ~ x + I(x^2))
  unname(coef(fit))
}

fit_table <- function(estimator_name, degree, method_name) {
  rows <- all_fits[all_fits$estimator == estimator_name & all_fits$degree == degree, ]
  data.frame(
    model_label = rows$model, method = method_name,
    intercept = rows$alpha, linear = rows$beta, quadratic = rows$gamma
  )
}
epoch_labels <- c(
  "Student-t" = "Epoch's Student-t",
  "Stochastic frontier" = "Epoch's frontier",
  "Spike + contention" = "Epoch's spike + contention"
)
fits <- rbind(
  fit_table("Student-t", 2, "Epoch's Student-t"),
  fit_table("Stochastic frontier", 2, "Epoch's frontier"),
  fit_table("Spike + contention", 2, "Epoch's spike + contention"),
  do.call(rbind, lapply(model_order, function(model_name) {
    coefficient <- floor_fit(model_name)
    data.frame(
      model_label = model_name, method = "Floor fit",
      intercept = coefficient[[1]], linear = coefficient[[2]], quadratic = coefficient[[3]]
    )
  }))
)
fits <- fits[fits$model_label %in% model_order, ]
student_linear <- fit_table("Student-t", 1, "Epoch's Student-t")

method_levels <- c("Epoch's Student-t", "Epoch's frontier", "Epoch's spike + contention", "Floor fit")

# --------------------------------------------------------------- style ------

text_color <- "#111827"
muted_text_color <- "#4B5563"
axis_color <- "#9CA3AF"
grid_color <- "#E5E7EB"
raw_color <- "#4B5563"
epoch_single_color <- "#D97706"
floor_color <- "#111827"
estimator_colors <- c(
  "Epoch's Student-t" = "#0072B2",
  "Epoch's frontier" = "#D55E00",
  "Epoch's spike + contention" = "#009E73",
  "Floor fit" = floor_color
)
estimator_linetypes <- c(
  "Epoch's Student-t" = "solid",
  "Epoch's frontier" = "dashed",
  "Epoch's spike + contention" = "dotted",
  "Floor fit" = "solid"
)
estimator_widths <- c(
  "Epoch's Student-t" = 1.05,
  "Epoch's frontier" = 1.05,
  "Epoch's spike + contention" = 1.05,
  "Floor fit" = 1.35
)
model_colors <- c(
  "GPT-5.6 Terra" = "#D55E00",
  "GPT-5.6 Sol" = "#CC79A7",
  "Claude Sonnet 5" = "#0072B2",
  "Claude Opus 5" = "#009E73"
)

curve_rows <- function(methods, models = model_order) {
  rows <- list()
  for (model_name in models) {
    model_points <- points[points$model_label == model_name, ]
    grid_millions <- seq(
      min(model_points$total_input_tokens) / 1e6,
      max(model_points$total_input_tokens) / 1e6,
      length.out = 300
    )
    for (method_name in methods) {
      coefficient <- fits[fits$model_label == model_name & fits$method == method_name, ]
      if (nrow(coefficient) != 1) stop(sprintf("Expected one %s fit for %s", method_name, model_name))
      rows[[length(rows) + 1]] <- data.frame(
        model_label = model_name, method = method_name,
        x_thousands = grid_millions * 1000,
        ttft_seconds = coefficient$intercept + coefficient$linear * grid_millions +
          coefficient$quadratic * grid_millions^2
      )
    }
  }
  result <- do.call(rbind, rows)
  result$model_label <- factor(result$model_label, levels = model_order)
  result$method <- factor(result$method, levels = method_levels)
  result
}

publication_theme <- function(show_x_title = TRUE, show_y_title = TRUE,
                              show_x_ticks = TRUE, show_y_ticks = TRUE) {
  theme_classic(base_size = 12, base_family = font_family) +
    theme(
      plot.background = element_rect(fill = "white", color = NA),
      panel.background = element_rect(fill = "white", color = NA),
      panel.grid.major = element_line(color = grid_color, linewidth = 0.45),
      panel.grid.minor = element_blank(),
      axis.line = element_line(color = axis_color, linewidth = 0.45),
      axis.ticks = element_line(color = axis_color, linewidth = 0.45),
      axis.ticks.length = unit(3.5, "pt"),
      axis.text = element_text(size = 10.5, color = muted_text_color),
      axis.text.x = if (show_x_ticks) element_text() else element_blank(),
      axis.text.y = if (show_y_ticks) element_text() else element_blank(),
      axis.ticks.x = if (show_x_ticks) element_line() else element_blank(),
      axis.ticks.y = if (show_y_ticks) element_line() else element_blank(),
      axis.title.x = if (show_x_title) {
        element_text(size = 11.5, face = "bold", color = text_color, margin = margin(t = 9, unit = "pt"))
      } else {
        element_blank()
      },
      axis.title.y = if (show_y_title) {
        element_text(size = 11.5, face = "bold", color = text_color, margin = margin(r = 9, unit = "pt"))
      } else {
        element_blank()
      },
      plot.title = element_text(size = 14, face = "bold", color = text_color, hjust = 0,
        margin = margin(b = 8, unit = "pt")),
      legend.position = "none",
      plot.margin = margin(3, 8, 3, 3, unit = "pt")
    )
}

make_panel <- function(model_name, methods, y_limits, y_breaks,
                       show_x_title, show_y_title,
                       show_x_ticks = TRUE, show_y_ticks = TRUE,
                       single_epoch_fit = FALSE) {
  model_points <- points[points$model_label == model_name, ]
  model_floor <- floor_points[floor_points$model_label == model_name, ]
  model_curves <- curve_rows(methods, model_name)
  if (single_epoch_fit) {
    colors <- estimator_colors
    colors[["Epoch's Student-t"]] <- epoch_single_color
  } else {
    colors <- estimator_colors
  }

  ggplot() +
    geom_point(
      data = model_points,
      aes(x = total_input_tokens / 1000, y = ttft_seconds),
      color = scales::alpha(raw_color, 0.42), shape = 16, size = 2.7, stroke = 0,
      inherit.aes = FALSE
    ) +
    geom_line(
      data = model_curves,
      aes(x = x_thousands, y = ttft_seconds, color = method, linetype = method, linewidth = method),
      lineend = "round", inherit.aes = FALSE
    ) +
    geom_point(
      data = model_floor,
      aes(x = total_input_tokens / 1000, y = ttft_seconds),
      color = floor_color, shape = 16, size = 2.9, stroke = 0,
      inherit.aes = FALSE
    ) +
    scale_color_manual(values = colors, drop = FALSE) +
    scale_linetype_manual(values = estimator_linetypes, drop = FALSE) +
    scale_linewidth_manual(values = estimator_widths, drop = FALSE) +
    scale_x_continuous(
      limits = c(0, 950), breaks = c(0, 300, 600, 900),
      labels = c("0", "300", "600", "900"), expand = expansion(mult = 0)
    ) +
    scale_y_continuous(limits = y_limits, breaks = y_breaks, expand = expansion(mult = 0)) +
    labs(title = model_name, x = "Input context (thousand tokens)", y = "Time to first token (s)") +
    publication_theme(show_x_title, show_y_title, show_x_ticks, show_y_ticks)
}

draw_figure_header <- function(title, subtitle, subtitle_y = 0.895) {
  grid.text(title,
    x = unit(0.055, "npc"), y = unit(0.955, "npc"), just = c("left", "top"),
    gp = gpar(fontfamily = font_family, fontface = "bold", fontsize = 16, col = text_color, lineheight = 1.08))
  grid.text(subtitle,
    x = unit(0.055, "npc"), y = unit(subtitle_y, "npc"), just = c("left", "top"),
    gp = gpar(fontfamily = font_family, fontsize = 11.5, col = muted_text_color, lineheight = 1.12))
}

draw_shared_legend <- function(labels, colors, linetypes, point_flags,
                               y = 0.105, fontsize = 10.8, widths = NULL) {
  handle_width <- 0.025
  text_gap <- 0.009
  column_gap <- 0.035
  text_width <- vapply(labels, function(label) {
    convertWidth(grobWidth(textGrob(label, gp = gpar(fontfamily = font_family, fontsize = fontsize))),
      "npc", valueOnly = TRUE)
  }, numeric(1))
  entry_width <- handle_width + text_gap + text_width
  if (sum(entry_width) + column_gap * (length(labels) - 1) > 0.94) {
    column_gap <- max(0.012, (0.94 - sum(entry_width)) / (length(labels) - 1))
  }
  total_width <- sum(entry_width) + column_gap * (length(labels) - 1)
  cursor <- (1 - total_width) / 2
  if (is.null(widths)) widths <- rep(2.6, length(labels))

  for (index in seq_along(labels)) {
    center <- cursor + handle_width / 2
    if (point_flags[[index]]) {
      grid.points(x = unit(center, "npc"), y = unit(y, "npc"), pch = 16, size = unit(5.5, "pt"),
        gp = gpar(col = colors[[index]]))
    } else {
      line_type <- switch(linetypes[[index]], solid = 1, dashed = 2, dotted = 3, 1)
      grid.lines(x = unit(c(cursor, cursor + handle_width), "npc"), y = unit(c(y, y), "npc"),
        gp = gpar(col = colors[[index]], lty = line_type, lwd = widths[[index]], lineend = "round"))
    }
    grid.text(labels[[index]],
      x = unit(cursor + handle_width + text_gap, "npc"), y = unit(y, "npc"), just = c("left", "center"),
      gp = gpar(fontfamily = font_family, fontsize = fontsize, col = text_color))
    cursor <- cursor + entry_width[[index]] + column_gap
  }
}

draw_panels <- function(panel_list, nrow, ncol, bounds, wspace, hspace = 0.08) {
  panel_width <- (bounds$right - bounds$left) / (ncol + (ncol - 1) * wspace)
  panel_height <- (bounds$top - bounds$bottom) / (nrow + (nrow - 1) * hspace)
  panel_index <- 1
  for (row in seq_len(nrow)) {
    for (column in seq_len(ncol)) {
      if (panel_index > length(panel_list)) next
      x_left <- bounds$left + (column - 1) * panel_width * (1 + wspace)
      y_bottom <- bounds$bottom + (nrow - row) * panel_height * (1 + hspace)
      print(panel_list[[panel_index]], vp = viewport(
        x = unit(x_left, "npc"), y = unit(y_bottom, "npc"),
        width = unit(panel_width, "npc"), height = unit(panel_height, "npc"),
        just = c("left", "bottom")
      ))
      panel_index <- panel_index + 1
    }
  }
}

export_figure <- function(stem, width, height, draw) {
  path_for <- function(ext) file.path(output_dir, paste0(stem, ".", ext))
  png(filename = path_for("png"), width = width, height = height, units = "in", res = 240,
    bg = "white", type = "cairo")
  draw()
  dev.off()
  svg(filename = path_for("svg"), width = width, height = height, bg = "white", pointsize = 12,
    family = font_family)
  draw()
  dev.off()
}

raw_legend_color <- scales::alpha(raw_color, 0.55)
single_fit_legend <- list(
  labels = c("Raw request", "Fastest request at that length", "Epoch's fit", "Floor fit"),
  colors = c(raw_legend_color, floor_color, epoch_single_color, floor_color),
  linetypes = c("solid", "solid", "solid", "solid"),
  points = c(TRUE, TRUE, FALSE, FALSE),
  widths = c(2.6, 2.6, 2.6, 3.2)
)
all_estimator_legend <- list(
  labels = c("Raw request", "Fastest request", unname(epoch_labels), "Floor fit"),
  colors = c(raw_legend_color, floor_color, unname(estimator_colors)),
  linetypes = c("solid", "solid", unname(estimator_linetypes)),
  points = c(TRUE, TRUE, FALSE, FALSE, FALSE, FALSE),
  widths = c(2.6, 2.6, 2.6, 2.6, 2.6, 3.2)
)

# ------------------------------------------------------------ figure 1 ------

figure_1_panels <- list(
  make_panel("GPT-5.6 Terra", "Epoch's Student-t", c(0, 30), c(0, 10, 20, 30),
    show_x_title = FALSE, show_y_title = TRUE, show_x_ticks = FALSE, show_y_ticks = TRUE, single_epoch_fit = TRUE),
  make_panel("GPT-5.6 Sol", "Epoch's Student-t", c(0, 30), c(0, 10, 20, 30),
    show_x_title = FALSE, show_y_title = FALSE, show_x_ticks = FALSE, show_y_ticks = FALSE, single_epoch_fit = TRUE),
  make_panel("Claude Sonnet 5", "Epoch's Student-t", c(0, 30), c(0, 10, 20, 30),
    show_x_title = TRUE, show_y_title = TRUE, show_x_ticks = TRUE, show_y_ticks = TRUE, single_epoch_fit = TRUE),
  make_panel("Claude Opus 5", "Epoch's Student-t", c(0, 30), c(0, 10, 20, 30),
    show_x_title = TRUE, show_y_title = FALSE, show_x_ticks = TRUE, show_y_ticks = FALSE, single_epoch_fit = TRUE)
)
for (index in seq_along(figure_1_panels)) {
  figure_1_panels[[index]] <- figure_1_panels[[index]] +
    geom_line(
      data = curve_rows("Floor fit", model_order[[index]]),
      aes(x = x_thousands, y = ttft_seconds),
      color = floor_color, linewidth = 1.35, lineend = "round", inherit.aes = FALSE
    )
}

export_figure("figure_1_headline_with_floor", 12.2, 9.2, function() {
  grid.newpage()
  draw_figure_header(
    "Fitted to its fastest requests, Claude Opus 5 curves upward like GPT-5.6",
    "Each dot is one API request; black dots are the fastest request at each context length.\nOrange: Epoch's quadratic-capable Student-t fit. Black: quadratic fit to the fastest requests."
  )
  draw_panels(figure_1_panels, 2, 2, list(left = 0.072, right = 0.965, top = 0.815, bottom = 0.155),
    wspace = 0.14, hspace = 0.20)
  draw_shared_legend(single_fit_legend$labels, single_fit_legend$colors, single_fit_legend$linetypes,
    single_fit_legend$points, y = 0.105, widths = single_fit_legend$widths)
})

# ------------------------------------------------------------ figure 2 ------

figure_2_panels <- list(
  make_panel("GPT-5.6 Terra", method_levels, c(0, 21), c(0, 5, 10, 15, 20),
    show_x_title = TRUE, show_y_title = TRUE),
  make_panel("GPT-5.6 Sol", method_levels, c(0, 21), c(0, 5, 10, 15, 20),
    show_x_title = TRUE, show_y_title = FALSE, show_y_ticks = FALSE)
)
export_figure("figure_2_gpt_estimators_with_floor", 11.7, 6.3, function() {
  grid.newpage()
  draw_figure_header(
    "For GPT-5.6, the floor fit lands on top of all three of Epoch's estimators",
    "When request-level noise is small, every estimator recovers the same serving curve."
  )
  draw_panels(figure_2_panels, 1, 2, list(left = 0.078, right = 0.965, top = 0.785, bottom = 0.205),
    wspace = 0.15, hspace = 0)
  draw_shared_legend(all_estimator_legend$labels, all_estimator_legend$colors, all_estimator_legend$linetypes,
    all_estimator_legend$points, y = 0.135, fontsize = 9.8, widths = all_estimator_legend$widths)
})

# ------------------------------------------------------------ figure 3 ------

figure_3_panels <- list(
  make_panel("Claude Sonnet 5", method_levels, c(0, 30), c(0, 5, 10, 15, 20, 25, 30),
    show_x_title = TRUE, show_y_title = TRUE),
  make_panel("Claude Opus 5", method_levels, c(0, 30), c(0, 5, 10, 15, 20, 25, 30),
    show_x_title = TRUE, show_y_title = FALSE, show_y_ticks = FALSE)
)
export_figure("figure_3_claude_estimators_with_floor", 11.7, 6.3, function() {
  grid.newpage()
  draw_figure_header(
    "Opus 5 curves upward at its floor; Epoch's estimators average in the slow requests",
    "Claude Sonnet 5 is linear under every estimator, including the floor fit. Epoch's three Opus 5 fits\npass through the cloud of slow requests; the floor fit passes through the fastest ones."
  )
  draw_panels(figure_3_panels, 1, 2, list(left = 0.078, right = 0.965, top = 0.785, bottom = 0.205),
    wspace = 0.15, hspace = 0)
  draw_shared_legend(all_estimator_legend$labels, all_estimator_legend$colors, all_estimator_legend$linetypes,
    all_estimator_legend$points, y = 0.135, fontsize = 9.8, widths = all_estimator_legend$widths)
})

# ------------------------------------------------------------ figure 4 ------

four_models <- model_order[1:4]
primary_forms <- c("GPT-5.6 Terra" = "quadratic", "GPT-5.6 Sol" = "quadratic",
  "Claude Sonnet 5" = "linear", "Claude Opus 5" = "linear")
x_million <- seq(1, 10, length.out = 451)
extrapolation_rows <- list()
for (model_name in four_models) {
  epoch_source <- if (primary_forms[[model_name]] == "quadratic") {
    fits[fits$method == "Epoch's Student-t", ]
  } else {
    student_linear
  }
  for (source_name in c("Epoch's fit", "Floor fit")) {
    source <- if (source_name == "Floor fit") fits[fits$method == "Floor fit", ] else epoch_source
    coefficient <- source[source$model_label == model_name, ]
    extrapolation_rows[[length(extrapolation_rows) + 1]] <- data.frame(
      model_label = model_name, source = source_name, input_million_tokens = x_million,
      ttft_minutes = (coefficient$intercept + coefficient$linear * x_million +
        coefficient$quadratic * x_million^2) / 60
    )
  }
}
extrapolation <- do.call(rbind, extrapolation_rows)
extrapolation$model_label <- factor(extrapolation$model_label, levels = four_models)
extrapolation$source <- factor(extrapolation$source, levels = c("Epoch's fit", "Floor fit"))
endpoints <- extrapolation[extrapolation$input_million_tokens == 10, ]
endpoint_labels <- do.call(rbind, lapply(four_models, function(model_name) {
  epoch_end <- endpoints$ttft_minutes[endpoints$model_label == model_name & endpoints$source == "Epoch's fit"]
  floor_end <- endpoints$ttft_minutes[endpoints$model_label == model_name & endpoints$source == "Floor fit"]
  data.frame(
    model_label = model_name, y = floor_end,
    label = sprintf("%s: Epoch's fit %.1f min, floor fit %.1f min", model_name, epoch_end, floor_end)
  )
}))
endpoint_labels$model_label <- factor(endpoint_labels$model_label, levels = four_models)

extrapolation_panel <- ggplot(extrapolation,
  aes(x = input_million_tokens, y = ttft_minutes, color = model_label,
    linetype = source, group = interaction(model_label, source))) +
  geom_line(linewidth = 1.2, lineend = "round") +
  geom_text(data = endpoint_labels,
    aes(x = 10.12, y = y, label = label, color = model_label),
    hjust = 0, vjust = 0.5, family = font_family, fontface = "bold", size = 3.6,
    show.legend = FALSE, inherit.aes = FALSE) +
  scale_color_manual(values = model_colors, drop = FALSE) +
  scale_linetype_manual(values = c("Epoch's fit" = "dashed", "Floor fit" = "solid")) +
  scale_x_continuous(breaks = c(1, 2, 4, 6, 8, 10), labels = c("1", "2", "4", "6", "8", "10"),
    expand = expansion(mult = 0)) +
  scale_y_continuous(breaks = c(0, 5, 10, 15, 20), labels = c("0", "5", "10", "15", "20"),
    expand = expansion(mult = 0)) +
  coord_cartesian(xlim = c(1, 10), ylim = c(0, 21), expand = FALSE, clip = "off") +
  labs(x = "Input context (million tokens)", y = "Time to first token (minutes)") +
  publication_theme(TRUE, TRUE, TRUE, TRUE) +
  theme(plot.margin = margin(6, 300, 6, 3, unit = "pt"))

export_figure("figure_4_extrapolation_with_floor", 12.6, 7.2, function() {
  grid.newpage()
  draw_figure_header(
    "Extrapolated from its floor, Claude Opus 5 TTFT rises like GPT-5.6 beyond 1 million tokens",
    "Dashed: Epoch's fits (quadratic GPT-5.6, linear Claude 5). Solid: quadratic fits to the fastest requests.\nMeasured data end below 1 million tokens; beyond that these are stress-test extrapolations, not forecasts.",
    subtitle_y = 0.895
  )
  print(extrapolation_panel, vp = viewport(
    x = unit(0.065, "npc"), y = unit(0.16, "npc"),
    width = unit(0.9, "npc"), height = unit(0.59, "npc"), just = c("left", "bottom")))
  draw_shared_legend(c("Epoch's fit", "Floor fit"), c(muted_text_color, muted_text_color),
    c("dashed", "solid"), c(FALSE, FALSE), y = 0.06, widths = c(2.6, 3.2))
})

# ----------------------------------------------------------- figure A1 ------

astra_panel <- make_panel("GPT-6 Astra", "Epoch's Student-t", c(0, 30), c(0, 10, 20, 30),
  show_x_title = TRUE, show_y_title = TRUE, single_epoch_fit = TRUE) +
  geom_line(
    data = curve_rows("Floor fit", "GPT-6 Astra"),
    aes(x = x_thousands, y = ttft_seconds),
    color = floor_color, linewidth = 1.35, lineend = "round", inherit.aes = FALSE
  )
export_figure("figure_a1_astra_with_floor", 8.4, 6.3, function() {
  grid.newpage()
  draw_figure_header(
    "GPT-6 Astra: Epoch's fit and the floor fit agree",
    "24 API requests; the two fits are nearly indistinguishable."
  )
  draw_panels(list(astra_panel), 1, 1, list(left = 0.072, right = 0.965, top = 0.785, bottom = 0.185),
    wspace = 0)
  draw_shared_legend(single_fit_legend$labels, single_fit_legend$colors, single_fit_legend$linetypes,
    single_fit_legend$points, y = 0.095, fontsize = 10.2, widths = single_fit_legend$widths)
})

floor_coefficients <- fits[fits$method == "Floor fit", ]
write.csv(floor_coefficients, file.path(output_dir, "floor_fit_coefficients.csv"), row.names = FALSE)
cat("Generated floor-overlay figures in", output_dir, "\n")
