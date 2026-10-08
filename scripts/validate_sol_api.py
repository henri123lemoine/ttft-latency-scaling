"""Offline schema, chronology and figure-membership checks for the Sol supplement."""
from collections import Counter
import csv
from datetime import datetime
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def csv_rows(path):
    with (ROOT / path).open(newline="") as handle:
        return list(csv.DictReader(handle))


def records(path):
    return [json.loads(line) for line in (ROOT / path).read_text().splitlines()]


def main():
    raw = records("data/raw/sol-api/20261006-sol-shared.jsonl")
    samples = [r for r in raw if r["type"] == "sample"]
    measured = [r for r in samples if r["kind"] == "measured"]
    assert len(samples) == 62 and len(measured) == 60
    assert len([r for r in samples if r["kind"] == "cache_setup"]) == 2
    assert all(r["valid"] and not r["flags"] for r in samples)
    assert abs(sum(r["estimated_cost_usd"] for r in samples) - 76.1724735) < 1e-9
    assert {r["attempt"] for r in samples} == {
        r["attempt"] for r in raw if r["type"] == "request_intent"
    }
    corpus_hash = hashlib.sha256((ROOT / "data/corpus/combined.txt").read_bytes()).hexdigest()
    for model, effort in (("gpt-6-sol", "none"), ("gpt-6.1-sol", "low")):
        manifest = json.loads((ROOT / f"config/sol-api/{model}-manifest.json").read_text())
        assert manifest["corpus_sha256"] == corpus_hash
        observed = [r for r in measured if r["model"] == model]
        assert len(observed) == 30
        assert {r["session"] for r in observed} == {manifest["session"]}
        assert Counter(r["block"] for r in observed) == {i: 6 for i in range(5)}
        assert [r["target_tokens"] for r in observed] == sum(manifest["schedules"], [])
        for r in observed:
            assert r["cache_read_tokens"] == 2051 and r["cache_write_tokens"] == 0
            assert r["total_input_tokens"] == r["target_tokens"] - 2
            assert r["new_input_tokens"] + 2051 == r["total_input_tokens"]
            assert r["reasoning_tokens"] == 0 and r["reasoning_effort"] == effort
            assert r["returned_model"] == model and r["returned_service_tier"] == "default"
            assert r["output_preview"] == "OK" and r["output_tokens"] == 5
            assert r["max_output_tokens"] == 32 and r["ttft_ns"] > 0
        for previous, current in zip(observed, observed[1:]):
            assert datetime.fromisoformat(current["request_started_at"]) > datetime.fromisoformat(previous["request_completed_at"])
    plots = csv_rows("outputs/sol-api/comparison/four_model_api_observations.csv")
    assert Counter(r["model"] for r in plots) == {
        "GPT-5.6 Sol": 30, "GPT-6 Astra": 24, "GPT-6 Sol": 30, "GPT-6.1 Sol": 30
    }
    sources = {"GPT-5.6 Sol": "data/raw/final/20260814T140715Z-bee825d8.jsonl"}
    expected = [("GPT-6 Sol" if r["model"] == "gpt-6-sol" else "GPT-6.1 Sol", r) for r in measured]
    for label, path in sources.items():
        expected.extend((label, r) for r in records(path) if r["type"] == "sample" and r["kind"] == "measured" and r["valid"])
    for path in sorted((ROOT / "data/raw/astra-api").glob("*.jsonl")):
        expected.extend(("GPT-6 Astra", r) for r in records(path.relative_to(ROOT)) if r["type"] == "sample" and r["kind"] == "measured" and r["valid"])
    def key(label, tokens, seconds):
        return label, round(float(tokens)), round(float(seconds), 8)
    assert Counter(key(r["model"], r["tokens"], r["ttft"]) for r in plots) == Counter(
        key(label, r["total_input_tokens"], r["ttft_ns"] / 1e9) for label, r in expected
    )
    assert len(csv_rows("outputs/sol-api/comparison/four_model_api_fit_curves.csv")) == 4800
    assert len(csv_rows("outputs/sol-api/comparison/four_model_api_minimum_points.csv")) == 24
    assert len(csv_rows("outputs/sol-api/huber_bootstrap.csv")) == 10000
    assert len(csv_rows("outputs/sol-api/asymmetric_bootstrap.csv")) == 800
    for stem in ("huber_bootstrap", "asymmetric_bootstrap"):
        assert all(r["gamma"] != "NA" for r in csv_rows(f"outputs/sol-api/{stem}.csv"))
    print("Sol supplement verified: 60 new measurements + 2 setup; all 114 plotted requests match released API logs.")


if __name__ == "__main__":
    main()
