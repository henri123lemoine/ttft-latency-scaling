"""Copy completed session logs into data/raw/<name> with the release redactions.

Usage: python scripts/prepare_claude_5_5_data.py live-results [label-substring] [name]
Defaults select the Claude 5.5 sessions into data/raw/claude-5.5.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from prepare_release_data import REDACTED_FIELDS

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    label_part = sys.argv[2] if len(sys.argv) > 2 else "-5-5"
    destination = ROOT / "data" / "raw" / (sys.argv[3] if len(sys.argv) > 3 else "claude-5.5")
    destination.mkdir(parents=True, exist_ok=True)
    for path in sorted(Path(sys.argv[1]).glob("*.jsonl")):
        records = [json.loads(line) for line in path.open()]
        label = records[0].get("label", "")
        if label_part not in label or records[-1].get("type") != "session_end":
            continue
        with open(destination / path.name, "w") as out:
            for record in records:
                out.write(json.dumps({k: v for k, v in record.items() if k not in REDACTED_FIELDS}) + "\n")
        print(f"{path.name}  {label}  {records[-1].get('status')}")


if __name__ == "__main__":
    main()
