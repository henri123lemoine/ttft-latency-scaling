"""Build docs/claude-5.5-post.html: the Claude 5.5 results as a self-contained page.

Takes the path to the personal-website checkout, whose stylesheet is inlined so the
page matches the blog. Usage: python scripts/build_claude_5_5_page.py ../personal-website
"""

from __future__ import annotations

import base64
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIGURES = ROOT / "figures" / "claude-5.5"


def figure(stem: str, alt: str) -> str:
    data = base64.b64encode((FIGURES / f"{stem}.png").read_bytes()).decode()
    return f'<p><img src="data:image/png;base64,{data}" alt="{alt}" width="1290" loading="lazy" /></p>'


def main() -> None:
    style = (Path(sys.argv[1]) / "public" / "static" / "style.css").read_text()
    body = (ROOT / "docs" / "claude-5.5-post.body.html").read_text()
    for stem, alt in FIGURE_ALTS.items():
        body = body.replace(f"{{{{{stem}}}}}", figure(stem, alt))
    page = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>TTFT scaling for the Claude 5.5 models</title>
<script>
if (window.matchMedia("(prefers-color-scheme: dark)").matches) document.documentElement.classList.add("dark");
</script>
<style>{style}</style>
<style>.blog-post .content img {{ display: block; max-width: 100%; height: auto; }}</style>
</head>
<body>
<div class="container">
<div class="layout">
<main>
<article class="blog-post">
<div class="post-header">
<h1>TTFT scaling for the Claude 5.5 models</h1>
<time datetime="2026-10-07">Oct 7, 2026</time>
</div>
<div class="content">
{body}
</div>
</article>
</main>
</div>
</div>
</body>
</html>
"""
    (ROOT / "docs" / "claude-5.5-post.html").write_text(page)


FIGURE_ALTS = {
    "figure_1_claude_5_5_with_floor": (
        "Four panels of TTFT against input context. Claude Haiku 5.5, Sonnet 5.5 and Opus 5.5 each show every "
        "request, Epoch's Student-t fit and a quadratic fit to the fastest request at each length; the fourth "
        "panel overlays the three floors. Haiku's two fits both curve upward. Sonnet's floor fit bends downward "
        "through a 5-second request at 900k tokens. Opus's floor fit is nearly straight."
    ),
    "figure_2_claude_5_5_curvature": (
        "Dot-and-whisker chart of the quadratic coefficient with 95% intervals. Haiku 5.5 excludes zero under "
        "the floor fit and the per-pass fit. Sonnet 5.5 and Opus 5.5 intervals are tens of units wide and "
        "straddle zero. Claude 5 intervals from the post are shown in grey for scale."
    ),
    "figure_3_claude_5_5_extrapolation": (
        "Extrapolated TTFT from 1 to 10 million tokens. Haiku 5.5 reaches 28.5 minutes under its floor fit and "
        "24.4 under Epoch's fit; Opus 5.5 reaches 4.8 and Sonnet 5.5 2.9 under Epoch's linear fits."
    ),
}

if __name__ == "__main__":
    main()
