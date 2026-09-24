#!/usr/bin/env Rscript

# Figures for the post's update: the second complete Claude sessions from
# Epoch's exploratory archive, drawn in the same layout as the original floor
# figures. Reads outputs/floor/update.json (analysis/floor_update.py) and
# outputs/floor/fits.json (analysis/floor.py).

script_arg <- commandArgs(trailingOnly = FALSE)
script_flag <- grep("^--file=", script_arg, value = TRUE)
script_path <- if (length(script_flag)) {
  normalizePath(sub("^--file=", "", script_flag[[1]]))
} else {
  normalizePath("analysis/figures_floor_update.R")
}
repo_root <- normalizePath(file.path(dirname(script_path), ".."))
args <- commandArgs(trailingOnly = TRUE)
output_dir <- if (length(args)) normalizePath(args[[1]], mustWork = FALSE) else file.path(repo_root, "figures/floor")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

source(file.path(dirname(script_path), "floor_theme.R"))

# ---------------------------------------------------------------- data ------

update <- jsonlite::fromJSON(file.path(repo_root, "outputs/floor/update.json"), simplifyVector = FALSE)
model_order <- c("Claude Sonnet 5", "Claude Opus 5")
session_keys <- c(headline = "headline", exploratory = "exploratory")
date_colors <- c("2026-08-13" = orange, "2026-08-14" = blue)
date_labels <- c("2026-08-13" = "Aug 13 session", "2026-08-14" = "Aug 14 session")

session_rows <- function(model_entry, key, field) {
  session <- model_entry[[key]]
  rows <- do.call(rbind, lapply(session[[field]], as.data.frame))
  rows$model <- model_entry$model
  rows$date <- session$date
  rows$session <- key
  rows
}
points <- do.call(rbind, lapply(update$models, function(m) rbind(session_rows(m, "headline", "points"), session_rows(m, "exploratory", "points"))))
floor_points <- do.call(rbind, lapply(update$models, function(m) rbind(session_rows(m, "headline", "floor"), session_rows(m, "exploratory", "floor"))))

fit_row <- function(model_name, label, date, fit) {
  data.frame(model = model_name, label = label, date = date, intercept = fit$alpha, linear = fit$beta,
    quadratic = fit$gamma, low = fit$gamma_ci95[[1]], high = fit$gamma_ci95[[2]], stringsAsFactors = FALSE)
}
fits <- do.call(rbind, lapply(update$models, function(m) rbind(
  fit_row(m$model, "headline", m$headline$date, m$headline$fit),
  fit_row(m$model, "exploratory", m$exploratory$date, m$exploratory$fit)
)))

evaluate <- function(coefficient, x_million) {
  coefficient$intercept + coefficient$linear * x_million + coefficient$quadratic * x_million^2
}

curve_rows <- function(model_name) {
  x_million <- seq(0.05, 0.9, length.out = 300)
  do.call(rbind, lapply(c("headline", "exploratory"), function(label) {
    coefficient <- fits[fits$model == model_name & fits$label == label, ]
    data.frame(label = label, date = coefficient$date, x_thousands = x_million * 1000, ttft_seconds = evaluate(coefficient, x_million))
  }))
}

# --------------------------------------------- figure 6: two sessions ------

session_panel <- function(model_name) {
  model_points <- points[points$model == model_name, ]
  model_floor <- floor_points[floor_points$model == model_name, ]
  curves <- curve_rows(model_name)
  curve_colors <- c("2026-08-13" = orange, "2026-08-14" = blue)
  curve_widths <- c("2026-08-13" = 1.1, "2026-08-14" = 1.1)
  curve_types <- c("2026-08-13" = "solid", "2026-08-14" = "solid")
  ggplot() +
    geom_point(data = model_points, aes(x = x * 1000, y = ttft, color = date), alpha = 0.3, size = 2.9, stroke = 0) +
    geom_line(data = curves, aes(x = x_thousands, y = ttft_seconds, color = date, linewidth = date, linetype = date), lineend = "round") +
    geom_point(data = model_floor, aes(x = x * 1000, y = ttft, color = date), size = 2.2, stroke = 0) +
    annotate("text", x = 40, y = 27, label = model_name, hjust = 0, vjust = 1, family = font_family, size = 4.1, color = body_ink) +
    scale_color_manual(values = curve_colors) +
    scale_linewidth_manual(values = curve_widths) +
    scale_linetype_manual(values = curve_types) +
    scale_x_continuous(limits = c(0, 950), breaks = c(0, 300, 600, 900), expand = expansion(mult = 0)) +
    scale_y_continuous(limits = c(0, 30), breaks = c(0, 10, 20, 30), expand = expansion(mult = 0)) +
    coord_cartesian(clip = "off") +
    panel_theme
}

panel_figure(
  "figure_6_second_sessions",
  "In a second session a day later, Claude Opus 5's floor curves\nupward again and Claude Sonnet 5's stays linear",
  "Same protocol and context grid. Opus's floor is 30% lower at long contexts on Aug 14 and half as\ncurved; Sonnet's two floors coincide.",
  list(
    list(kind = "point", color = orange, label = "Aug 13 session"),
    list(kind = "point", color = blue, label = "Aug 14 session"),
    list(kind = "line", color = body_ink, label = "Floor fit per session", lwd = 3)
  ),
  lapply(model_order, session_panel),
  ncol = 2,
  x_label = "Input context (thousand tokens)",
  y_header = "Time to first token (s)",
  caption = "Faint dots: every request in each session. Solid dots: each session's fastest request per length. Lines: quadratic\nfit to those. Sonnet: Aug 14 is Epoch's headline session. Opus: Aug 13 is."
)

# ------------------------------------------- figure 7: curvature update ----

reference <- update$reference
interval_rows <- rbind(
  do.call(rbind, lapply(update$models, function(m) {
    session_label <- function(key, suffix) sprintf("%s, %s (%d passes)%s", m$model, format(as.Date(m[[key]]$date), "%b %d"), m[[key]]$blocks, suffix)
    rbind(
      data.frame(label = session_label("headline", ", in the post"), date = m$headline$date, estimate = m$headline$fit$gamma,
        low = m$headline$fit$gamma_ci95[[1]], high = m$headline$fit$gamma_ci95[[2]]),
      data.frame(label = session_label("exploratory", ", new"), date = m$exploratory$date, estimate = m$exploratory$fit$gamma,
        low = m$exploratory$fit$gamma_ci95[[1]], high = m$exploratory$fit$gamma_ci95[[2]])
    )
  })),
  do.call(rbind, lapply(names(reference), function(model_name) {
    r <- reference[[model_name]]
    data.frame(label = sprintf("%s (%d passes), in the post", model_name, r$blocks), date = "reference", estimate = r$gamma,
      low = r$gamma_ci95[[1]], high = r$gamma_ci95[[2]])
  }))
)
interval_rows$label <- factor(interval_rows$label, levels = rev(interval_rows$label))
interval_colors <- c("2026-08-13" = orange, "2026-08-14" = blue, "reference" = muted)

curvature_panel <- ggplot(interval_rows, aes(y = label, color = date)) +
  geom_vline(xintercept = 0, color = body_ink, linewidth = 0.5) +
  geom_errorbarh(aes(xmin = low, xmax = high), height = 0, linewidth = 1.1, lineend = "round") +
  geom_point(aes(x = estimate), size = 3) +
  scale_color_manual(values = interval_colors) +
  scale_x_continuous(limits = c(-6, 20), breaks = seq(-5, 20, 5), expand = expansion(mult = 0)) +
  panel_theme +
  theme(
    panel.grid.major.y = element_blank(),
    panel.grid.major.x = element_line(color = grid_line, linewidth = 0.5),
    axis.line.x = element_blank(),
    axis.text.y = element_text(size = 10.5, color = body_ink, hjust = 0, margin = margin(r = 10))
  )

export_figure("figure_7_curvature_update", function() {
  grid.newpage()
  text_grob("Claude Opus 5 curves upward in both sessions; Claude Sonnet 5 in neither", 0.08, 0.955, 15.5, face = "bold")
  draw_legend(list(
    list(kind = "line", color = orange, label = "Aug 13 session", lwd = 3),
    list(kind = "line", color = blue, label = "Aug 14 session", lwd = 3),
    list(kind = "line", color = muted, label = "GPT reference, from the post", lwd = 3)
  ), 0.87)
  place(curvature_panel, 0.08, 0.30, 0.84, 0.53)
  text_grob("Quadratic coefficient of the floor fit (seconds per million tokens squared), 95% interval",
    0.08 + 0.84 * 0.6, 0.275, 11, color = body_ink, just = c("center", "top"))
  draw_footer("Each interval is a quadratic fit to the fastest request at each of eight context lengths. Opus's two sessions differ\nin level, slope, and curvature (p = 0.04 for the curvature), so they are not pooled.",
    caption_y = 0.135)
}, width = 8.6, height = 6.6)

# ----------------------------------------- figure 8: extrapolation update --

epoch_fits <- jsonlite::fromJSON(file.path(repo_root, "outputs/floor/fits.json"), simplifyVector = FALSE)$models
sol <- Filter(function(m) m$model == "GPT-5.6 Sol", epoch_fits)[[1]]$floor_fit$quadratic
sol_fit <- data.frame(intercept = sol$alpha, linear = sol$beta, quadratic = sol$gamma)
x_million <- seq(1, 10, length.out = 451)
curve <- function(name, coefficient, linetype) {
  data.frame(name = name, linetype = linetype, x = x_million, minutes = evaluate(coefficient, x_million) / 60)
}
extrapolation <- rbind(
  curve("Claude Sonnet 5, Aug 14 (in the post)", fits[fits$model == "Claude Sonnet 5" & fits$label == "headline", ], "solid"),
  curve("Claude Sonnet 5, Aug 13", fits[fits$model == "Claude Sonnet 5" & fits$label == "exploratory", ], "31"),
  curve("Claude Opus 5, Aug 13 (in the post)", fits[fits$model == "Claude Opus 5" & fits$label == "headline", ], "solid"),
  curve("Claude Opus 5, Aug 14", fits[fits$model == "Claude Opus 5" & fits$label == "exploratory", ], "31"),
  curve("GPT-5.6 Sol (in the post)", sol_fit, "solid")
)
curve_names <- unique(extrapolation$name)
extrapolation$name <- factor(extrapolation$name, levels = curve_names)
curve_colors <- c(teal, teal, blue, blue, orange)
names(curve_colors) <- curve_names
curve_types <- c("solid", "31", "solid", "31", "solid")
names(curve_types) <- curve_names
ends <- extrapolation[extrapolation$x == 10, ]
end_text <- c(
  "Claude Sonnet 5, Aug 14 (in the post)" = "%.1f min (Sonnet, Aug 14)",
  "Claude Sonnet 5, Aug 13" = "%.1f min (Sonnet, Aug 13)",
  "Claude Opus 5, Aug 13 (in the post)" = "%.1f min (Opus, Aug 13)",
  "Claude Opus 5, Aug 14" = "%.1f min (Opus, Aug 14)",
  "GPT-5.6 Sol (in the post)" = "%.1f min (Sol)"
)
ends$label <- sprintf(end_text[as.character(ends$name)], ends$minutes)
sonnet_ends <- grepl("^Claude Sonnet", ends$name)
ends$minutes[sonnet_ends] <- ends$minutes[sonnet_ends] + c(-0.45, 0.45)

extrapolation_panel <- ggplot(extrapolation, aes(x = x, y = minutes, color = name, linetype = name, group = name)) +
  geom_line(linewidth = 1.05, lineend = "round") +
  geom_text(data = ends, aes(x = 10.15, y = minutes, label = label, color = name), hjust = 0, vjust = 0.5,
    family = font_family, size = 3.7, inherit.aes = FALSE) +
  scale_color_manual(values = curve_colors) +
  scale_linetype_manual(values = curve_types) +
  scale_x_continuous(breaks = c(1, 3, 5, 7, 9, 11), limits = c(1, 12.4), expand = expansion(mult = 0)) +
  scale_y_continuous(breaks = c(0, 5, 10, 15, 20), limits = c(0, 21), expand = expansion(mult = 0)) +
  coord_cartesian(clip = "off") +
  panel_theme

export_figure("figure_8_extrapolation_update", function() {
  grid.newpage()
  text_grob("Extrapolated to 10 million tokens, Claude Opus 5 lands between\n9 and 18 minutes depending on the session; Sonnet near 3", 0.08, 0.965, 15.5, face = "bold")
  draw_legend(list(
    list(kind = "line", color = teal, label = "Claude Sonnet 5"),
    list(kind = "line", color = blue, label = "Claude Opus 5"),
    list(kind = "line", color = orange, label = "GPT-5.6 Sol"),
    list(kind = "line", color = body_ink, label = "Aug 13 or in the post"),
    list(kind = "line", color = body_ink, label = "Aug 14", lty = "31")
  ), 0.868)
  text_grob("Time to first token (minutes)", 0.08, 0.815, 11, color = body_ink)
  place(extrapolation_panel, 0.08, 0.215, 0.84, 0.57)
  text_grob("Input context (million tokens)", 0.08 + 0.84 * 0.4, 0.20, 11, color = body_ink, just = c("center", "top"))
  draw_footer("Measured data end below 1 million tokens; beyond that, these are stress-test extrapolations, not forecasts.\nAll curves are quadratic fits to the fastest request at each length.")
})

write.csv(fits, file.path(output_dir, "floor_update_coefficients.csv"), row.names = FALSE)
cat("Generated floor update figures in", output_dir, "\n")
