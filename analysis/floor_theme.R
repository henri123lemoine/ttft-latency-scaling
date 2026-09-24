# Shared style and layout helpers for the floor figures: the Epoch web-post palette,
# Inter type, panel theme, and the grid-based page layout. Sourced by
# figures_floor.R and figures_floor_update.R, which define repo_root and
# output_dir before sourcing.

suppressPackageStartupMessages({
  library(ggplot2)
  library(grid)
})

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
font_family <- "Inter"

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

draw_footer <- function(caption, caption_y = 0.085) {
  if (nzchar(caption)) text_grob(caption, 0.08, caption_y, 10, color = muted)
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
