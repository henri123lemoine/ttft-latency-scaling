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

raw_session_rows <- function(directory, label_pattern, panel) {
  do.call(rbind, lapply(sort(list.files(file.path(repo_root, directory), pattern = "\\.jsonl$", full.names = TRUE)), function(path) {
    session <- jsonlite::fromJSON(readLines(path, n = 1))
    if (!grepl(label_pattern, session$label)) return(NULL)
    records <- jsonlite::stream_in(file(path), verbose = FALSE)
    records <- records[records$type == "sample" & records$kind == "measured" & records$valid, ]
    rows(panel, records$total_input_tokens / 1e6, records$ttft_ns / 1e9, paste(session$session, records$repetition))
  }))
}

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
  raw_session_rows("data/raw/luna-openrouter", "shared-prefix$", "GPT-6 Luna (via OpenRouter)"),
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

# Least squares on alpha + beta x + gamma x^2 with beta >= 0 and gamma >= 0: TTFT cannot
# fall, or grow ever more slowly, with context. With two bounds the optimum is the best
# feasible fit among the four ways of pinning them.
constrained_quadratic <- function(x, y) {
  candidates <- list(
    list(formula = y ~ x + I(x^2), bound = ""),
    list(formula = y ~ x, bound = "curvature"),
    list(formula = y ~ I(x^2), bound = "slope"),
    list(formula = y ~ 1, bound = "slope and curvature")
  )
  best <- NULL
  for (candidate in candidates) {
    model <- lm(candidate$formula, data.frame(x = x, y = y))
    coefficient <- c(alpha = unname(coef(model)[1]), beta = 0, gamma = 0)
    if ("x" %in% names(coef(model))) coefficient[["beta"]] <- coef(model)[["x"]]
    if ("I(x^2)" %in% names(coef(model))) coefficient[["gamma"]] <- coef(model)[["I(x^2)"]]
    if (coefficient[["beta"]] < 0 || coefficient[["gamma"]] < 0) next
    rss <- sum(resid(model)^2)
    if (is.null(best) || rss < best$rss) best <- list(coefficient = coefficient, rss = rss, bound = candidate$bound)
  }
  best
}

fit_panel <- function(panel) {
  data <- observations[observations$panel == panel, ]
  data$block <- factor(data$block)
  student <- fit_student(data, 2)
  linear <- fit_student(data, 1)
  floor <- aggregate(y ~ x, data, min)
  floor_model <- lm(y ~ x + I(x^2), floor)
  interval <- confint(floor_model)["I(x^2)", ]
  constrained <- constrained_quadratic(floor$x, floor$y)
  pass_gammas <- vapply(split(data, data$block), function(pass) unname(coef(lm(y ~ x + I(x^2), pass))[3]), numeric(1))
  pass_half <- qt(0.975, length(pass_gammas) - 1) * sd(pass_gammas) / sqrt(length(pass_gammas))
  list(
    points = data, floor = floor,
    summary = data.frame(
      panel = panel, passes = nlevels(data$block), requests = nrow(data),
      student_alpha = unname(student$beta["(Intercept)"]), student_beta = unname(student$beta["x"]),
      student_gamma = unname(student$beta["I(x^2)"]),
      student_delta_aicc = linear$aicc - student$aicc,
      student_linear_alpha = unname(linear$beta["(Intercept)"]), student_linear_beta = unname(linear$beta["x"]),
      floor_alpha = constrained$coefficient[["alpha"]], floor_beta = constrained$coefficient[["beta"]],
      floor_gamma = constrained$coefficient[["gamma"]], floor_bound = constrained$bound,
      unconstrained_floor_alpha = unname(coef(floor_model)[1]), unconstrained_floor_beta = unname(coef(floor_model)[2]),
      unconstrained_floor_gamma = unname(coef(floor_model)[3]),
      unconstrained_floor_gamma_low = interval[[1]], unconstrained_floor_gamma_high = interval[[2]],
      unconstrained_floor_p = summary(floor_model)$coefficients["I(x^2)", "Pr(>|t|)"],
      per_pass_gamma = mean(pass_gammas), per_pass_gamma_low = mean(pass_gammas) - pass_half,
      per_pass_gamma_high = mean(pass_gammas) + pass_half
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
  floor_note <- if (nzchar(s$floor_bound)) {
    sprintf("%.1f floor (%s held at 0)", s$floor_gamma, s$floor_bound)
  } else {
    sprintf("%.1f floor (%.1f to %.1f)", s$floor_gamma, s$unconstrained_floor_gamma_low, s$unconstrained_floor_gamma_high)
  }
  note <- sprintf("%d passes. Curvature: %.1f Student-t,\n%s", s$passes, s$student_gamma, floor_note)
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
  text_grob("Time to first token against context length, every model measured so far", 0.05, 0.987, 17, face = "bold")
  text_grob("Same shared-prefix protocol throughout. Curvature is the quadratic coefficient in seconds per million tokens squared.\nThe floor fit may not slope or bend downward; its 95% interval is in brackets where neither limit binds.",
    0.05, 0.969, 11.5, color = muted)
  draw_legend(list(
    list(kind = "line", color = teal, label = "Epoch's Student-t fit"),
    list(kind = "line", color = floor_color, label = "Floor fit", lwd = 3),
    list(kind = "point", color = scales::alpha(dot, 0.8), label = "Raw request"),
    list(kind = "point", color = floor_color, label = "Fastest request")
  ), 0.938, x = 0.05)
  top <- 0.92
  bottom <- 0.06
  gap_x <- 0.035
  gap_y <- 0.025
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
  grid.lines(x = unit(c(0.05, 0.95), "npc"), y = unit(c(0.032, 0.032), "npc"), gp = gpar(col = grid_line, lwd = 1))
  text_grob("GPT and Claude 5 data: Epoch AI (CC-BY). Claude 5.5 and GPT-6 Luna data: own sessions on Epoch's collector. Fits recomputed identically for every panel.",
    0.05, 0.025, 9.5, color = muted, just = c("left", "top"))
  text_grob("henrilemoine.com", 0.95, 0.025, 9.5, color = muted, just = c("right", "top"))
}, width = 12.6, height = 19)

# ------------------------------------------------------- extrapolation ------
# Epoch's fit is the Student-t degree its AICc prefers; the floor fit is the
# constrained quadratic, drawn dashed where its curvature is held at zero.

family_colors <- c(
  "GPT-5.6 Terra" = magenta, "GPT-5.6 Sol" = orange, "GPT-6 Luna (via OpenRouter)" = "#d060a0", "GPT-6 Astra" = "#a03010", "GPT-6 Sol" = "#c89000",
  "GPT-6.1 Sol" = "#806040", "Claude Sonnet 5, Aug 14" = teal, "Claude Sonnet 5, Aug 13" = "#70c8c8",
  "Claude Opus 5, Aug 13" = blue, "Claude Opus 5, Aug 14" = "#70a0f0", "Claude Haiku 5.5" = "#8030c0",
  "Claude Sonnet 5.5" = "#208050", "Claude Opus 5.5" = "#102060"
)
x_million <- seq(1, 10, length.out = 451)
extrapolation_rows <- function(source) do.call(rbind, lapply(panel_order, function(panel) {
  s <- summary_table[summary_table$panel == panel, ]
  seconds <- if (source == "floor") {
    s$floor_alpha + s$floor_beta * x_million + s$floor_gamma * x_million^2
  } else if (s$student_delta_aicc > 0) {
    s$student_alpha + s$student_beta * x_million + s$student_gamma * x_million^2
  } else {
    s$student_linear_alpha + s$student_linear_beta * x_million
  }
  degree <- if (source == "floor") {
    if (s$floor_gamma > 0) "quadratic" else "linear"
  } else if (s$student_delta_aicc > 0) "quadratic" else "linear"
  data.frame(panel = panel, x = x_million, minutes = seconds / 60, degree = degree)
}))

spread_labels <- function(ends, gap) {
  ends <- ends[order(ends$minutes), ]
  ends$label_y <- ends$minutes
  for (i in seq_len(nrow(ends))[-1]) ends$label_y[i] <- max(ends$label_y[i], ends$label_y[i - 1] + gap)
  ends
}

extrapolation_panel <- function(source, y_max = 30) {
  curves <- extrapolation_rows(source)
  curves$panel <- factor(curves$panel, levels = panel_order)
  ends <- spread_labels(curves[curves$x == 10, ], gap = y_max * 0.043)
  ends$label <- sprintf("%.1f min  %s", ends$minutes, ends$panel)
  ggplot(curves, aes(x = x, y = minutes, color = panel, group = panel)) +
    geom_line(aes(linetype = degree), linewidth = 0.95, lineend = "round") +
    geom_segment(data = ends, aes(x = 10.03, xend = 10.2, y = minutes, yend = label_y), linewidth = 0.3) +
    geom_text(data = ends, aes(x = 10.25, y = label_y, label = label), hjust = 0, vjust = 0.5,
      family = font_family, size = 3.5) +
    scale_color_manual(values = family_colors) +
    scale_linetype_manual(values = c(linear = "22", quadratic = "solid")) +
    scale_x_continuous(breaks = c(1, 3, 5, 7, 9), limits = c(1, 13.6), expand = expansion(mult = 0)) +
    scale_y_continuous(breaks = seq(0, y_max, 10), limits = c(0, y_max + 1), expand = expansion(mult = 0)) +
    coord_cartesian(clip = "off") +
    panel_theme
}

export_figure("figure_all_models_extrapolation", function() {
  grid.newpage()
  text_grob("Extrapolated to 10 million tokens, every model measured so far", 0.08, 0.98, 15.5, face = "bold")
  text_grob("Top: Epoch's Student-t fit. Bottom: floor fit, which may not slope or bend downward.",
    0.08, 0.955, 11.5, color = muted)
  draw_legend(list(
    list(kind = "line", color = body_ink, label = "Quadratic fit"),
    list(kind = "line", color = body_ink, label = "Linear fit", lty = "22")
  ), 0.925)
  text_grob("Epoch's fit: time to first token (minutes)", 0.08, 0.90, 11, color = body_ink)
  place(extrapolation_panel("epoch"), 0.08, 0.525, 0.84, 0.36)
  text_grob("Floor fit: time to first token (minutes)", 0.08, 0.495, 11, color = body_ink)
  place(extrapolation_panel("floor"), 0.08, 0.12, 0.84, 0.36)
  text_grob("Input context (million tokens)", 0.08 + 0.84 * 0.33, 0.108, 11, color = body_ink, just = c("center", "top"))
  text_grob("Measured data end below 1 million tokens; beyond that, these are stress-test extrapolations, not forecasts.\nClaude Sonnet 5.5's floor would bend downward, so its curvature is held at zero. Claude Opus 5.5's floor\ncurvature is undetermined (95% interval -11 to 28).",
    0.08, 0.088, 10, color = muted)
  grid.lines(x = unit(c(0.08, 0.92), "npc"), y = unit(c(0.035, 0.035), "npc"), gp = gpar(col = grid_line, lwd = 1))
  text_grob("GPT and Claude 5 data: Epoch AI (CC-BY). Claude 5.5 and GPT-6 Luna data: own sessions.", 0.08, 0.026, 9.5, color = muted, just = c("left", "top"))
  text_grob("henrilemoine.com", 0.92, 0.026, 9.5, color = muted, just = c("right", "top"))
}, width = 8.6, height = 12.4)

extrapolated <- rbind(cbind(source = "epoch", extrapolation_rows("epoch")), cbind(source = "floor", extrapolation_rows("floor")))
write.csv(extrapolated[extrapolated$x == 10, c("source", "panel", "degree", "minutes")],
  file.path(output_dir, "all_models_ttft_at_10m.csv"), row.names = FALSE)

# ----------------------------------------------------------- curvature ------
# Two intervals per session, as in the post: the unconstrained floor fit, and
# one quadratic per chronological pass.

interval_rows <- do.call(rbind, lapply(panel_order, function(panel) {
  s <- summary_table[summary_table$panel == panel, ]
  label <- sprintf("%s (%d passes)", panel, s$passes)
  rbind(
    data.frame(label = label, method = "Floor fit", estimate = s$unconstrained_floor_gamma,
      low = s$unconstrained_floor_gamma_low, high = s$unconstrained_floor_gamma_high),
    data.frame(label = label, method = "One quadratic per pass", estimate = s$per_pass_gamma,
      low = s$per_pass_gamma_low, high = s$per_pass_gamma_high)
  )
}))
interval_rows$label <- factor(interval_rows$label, levels = rev(unique(interval_rows$label)))
interval_rows$method <- factor(interval_rows$method, levels = c("Floor fit", "One quadratic per pass"))

curvature_panel <- ggplot(interval_rows, aes(y = label, color = method)) +
  geom_vline(xintercept = 0, color = body_ink, linewidth = 0.5) +
  geom_errorbarh(aes(xmin = low, xmax = high), height = 0, linewidth = 1.1,
    position = position_dodge(width = 0.55), lineend = "round") +
  geom_point(aes(x = estimate), size = 2.8, position = position_dodge(width = 0.55)) +
  scale_color_manual(values = c("Floor fit" = floor_color, "One quadratic per pass" = teal)) +
  scale_x_continuous(limits = c(-50, 50), breaks = seq(-40, 40, 20), expand = expansion(mult = 0)) +
  panel_theme +
  theme(
    panel.grid.major.y = element_blank(),
    panel.grid.major.x = element_line(color = grid_line, linewidth = 0.5),
    axis.line.x = element_blank(),
    axis.text.y = element_text(size = 10.5, color = body_ink, hjust = 0, margin = margin(r = 10))
  )

export_figure("figure_all_models_curvature", function() {
  grid.newpage()
  text_grob("Curvature of time to first token, every model measured so far", 0.08, 0.972, 15.5, face = "bold")
  draw_legend(list(
    list(kind = "line", color = floor_color, label = "Floor fit, 95% interval", lwd = 3),
    list(kind = "line", color = teal, label = "One quadratic per chronological pass, mean and 95% interval", lwd = 3)
  ), 0.925)
  place(curvature_panel, 0.08, 0.19, 0.84, 0.71)
  text_grob("Quadratic coefficient of TTFT in context length (seconds per million tokens squared)",
    0.08 + 0.84 * 0.62, 0.175, 11, color = body_ink, just = c("center", "top"))
  text_grob("The floor fit uses only the fastest request at each length, here without the no-downward limit so that its\ninterval is the ordinary one. The per-pass fit uses every request in one sweep over all lengths.",
    0.08, 0.115, 10, color = muted)
  grid.lines(x = unit(c(0.08, 0.92), "npc"), y = unit(c(0.045, 0.045), "npc"), gp = gpar(col = grid_line, lwd = 1))
  text_grob("GPT and Claude 5 data: Epoch AI (CC-BY). Claude 5.5 and GPT-6 Luna data: own sessions.", 0.08, 0.033, 9.5, color = muted, just = c("left", "top"))
  text_grob("henrilemoine.com", 0.92, 0.033, 9.5, color = muted, just = c("right", "top"))
}, width = 8.6, height = 9.6)

print(format(summary_table[, c("panel", "passes", "student_gamma", "student_delta_aicc", "floor_beta", "floor_gamma",
  "floor_bound", "unconstrained_floor_gamma")], digits = 3), row.names = FALSE)
