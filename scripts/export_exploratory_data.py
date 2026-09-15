#!/usr/bin/env python3
"""Validate and export the separately released exploratory TTFT sessions.

The exporter is deliberately descriptive. It does not fit or pool the sessions,
and it does not feed the headline analysis or Figures 1--4.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import re
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = ROOT / "config" / "exploratory_sessions.json"
RAW_DIR = ROOT / "data" / "raw" / "exploratory"
SCHEDULE_DIR = ROOT / "data" / "schedules" / "exploratory"
MANIFEST_PATH = ROOT / "data" / "exploratory_session_manifest.csv"
OBSERVATIONS_PATH = ROOT / "outputs" / "exploratory" / "request_observations.csv"
SUMMARY_PATH = ROOT / "outputs" / "exploratory" / "session_summary.csv"

FORBIDDEN_FIELDS = {
    "hostname",
    "network_label",
    "platform",
    "request_id",
    "response_id",
    "retry_after",
    "ratelimit_reset_tokens",
    "ratelimit_remaining_tokens",
    "hard_cost_limit_usd",
}
SECRET_PATTERNS = {
    "credential environment-variable name": re.compile(
        r"(?:OPENAI|ANTHROPIC|GEMINI|OPENROUTER)_API_KEY", re.I
    ),
    "authorization header": re.compile(r"authorization\s*[:=]", re.I),
    "API key header": re.compile(r"x-api-key\s*[:=]", re.I),
    "OpenAI-style secret": re.compile(r"\bsk-[A-Za-z0-9_-]{20,}\b"),
}

MANIFEST_FIELDS = [
    "model",
    "provider",
    "api_model",
    "session_id",
    "session_label",
    "schema_version",
    "design_status",
    "analysis_role",
    "mode",
    "session_started_at",
    "last_recorded_at",
    "declared_context_lengths",
    "observed_context_lengths",
    "planned_repetitions",
    "observed_repetitions_by_length",
    "chronological_blocks",
    "measured_requests",
    "nonmeasured_requests",
    "has_complete_session_end",
    "has_request_boundaries",
    "raw_file",
    "schedule_file",
    "notes",
]

OBSERVATION_FIELDS = [
    "model",
    "provider",
    "api_model",
    "session_id",
    "session_label",
    "schema_version",
    "design_status",
    "analysis_role",
    "mode",
    "sequence",
    "block",
    "repetition",
    "target_tokens",
    "prepared_tokens",
    "total_input_tokens",
    "new_input_tokens",
    "cache_read_tokens",
    "cache_write_tokens",
    "output_tokens",
    "reasoning_tokens",
    "thinking_blocks",
    "timestamp",
    "request_started_at",
    "request_completed_at",
    "headers_seconds",
    "first_event_seconds",
    "first_content_seconds",
    "ttft_seconds",
    "total_seconds",
    "request_bytes",
    "status_code",
    "returned_model",
    "requested_service_tier",
    "returned_service_tier",
    "instruction_mode",
    "nonce_position",
    "output_compliant",
    "prompt_sha256",
    "stable_prefix_sha256",
    "cache_key_sha256",
    "shared_cache_prefix_requested_tokens",
    "estimated_cost_usd",
]

SUMMARY_FIELDS = [
    "model",
    "provider",
    "session_id",
    "design_status",
    "mode",
    "measured_requests",
    "chronological_blocks",
    "minimum_target_tokens",
    "maximum_target_tokens",
    "minimum_reported_input_tokens",
    "maximum_reported_input_tokens",
    "median_ttft_seconds",
    "total_estimated_cost_usd",
]

SCHEDULE_FIELDS = [
    "sequence",
    "block",
    "target_tokens",
    "timestamp",
    "request_started_at",
    "request_completed_at",
]


def fail(message: str) -> None:
    raise AssertionError(message)


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    return [json.loads(line) for line in path.read_text().splitlines() if line]


def csv_bytes(fieldnames: list[str], rows: list[dict[str, Any]]) -> bytes:
    buffer = io.StringIO(newline="")
    writer = csv.DictWriter(
        buffer, fieldnames=fieldnames, extrasaction="raise", lineterminator="\n"
    )
    writer.writeheader()
    writer.writerows(rows)
    return buffer.getvalue().encode("utf-8")


def seconds(record: dict[str, Any], field: str) -> str:
    value = record.get(field)
    return "" if value is None else format(value / 1_000_000_000, ".9f")


def text_value(value: Any) -> Any:
    if value is None:
        return ""
    if isinstance(value, bool):
        return str(value).lower()
    return value


def median(values: list[float]) -> float:
    ordered = sorted(values)
    middle = len(ordered) // 2
    if len(ordered) % 2:
        return ordered[middle]
    return (ordered[middle - 1] + ordered[middle]) / 2


def timestamp_for(record: dict[str, Any]) -> str:
    return str(
        record.get("request_completed_at")
        or record.get("request_started_at")
        or record.get("timestamp")
        or ""
    )


def nested_forbidden_fields(value: Any) -> set[str]:
    found: set[str] = set()
    if isinstance(value, dict):
        for key, child in value.items():
            if key in FORBIDDEN_FIELDS:
                found.add(key)
            found.update(nested_forbidden_fields(child))
    elif isinstance(value, list):
        for child in value:
            found.update(nested_forbidden_fields(child))
    return found


def validate_hash(value: Any, path: Path, field: str) -> None:
    if value in (None, ""):
        return
    if not isinstance(value, str) or re.fullmatch(r"[0-9a-f]{64}", value) is None:
        fail(f"{path}: malformed {field}")


def build_exports() -> dict[Path, bytes]:
    configuration = json.loads(CONFIG_PATH.read_text())
    specifications = configuration["sessions"]
    expected_ids = [specification["session_id"] for specification in specifications]
    actual_ids = sorted(path.stem for path in RAW_DIR.glob("*.jsonl"))
    if sorted(expected_ids) != actual_ids:
        fail("exploratory raw-file set differs from the reviewed session registry")

    manifest_rows: list[dict[str, Any]] = []
    observation_rows: list[dict[str, Any]] = []
    summary_rows: list[dict[str, Any]] = []
    schedules: dict[Path, bytes] = {}

    for specification in specifications:
        session_id = specification["session_id"]
        path = RAW_DIR / f"{session_id}.jsonl"
        raw_text = path.read_text()
        for label, pattern in SECRET_PATTERNS.items():
            if pattern.search(raw_text):
                fail(f"{path}: possible {label}")
        records = read_jsonl(path)
        if not records or records[0].get("type") != "session":
            fail(f"{path}: first record is not a session header")
        header = records[0]
        if header.get("session") != session_id:
            fail(f"{path}: session ID mismatch")
        if header.get("corpus_sha256") != configuration["corpus_sha256"]:
            fail(f"{path}: corpus hash mismatch")
        forbidden = set().union(*(nested_forbidden_fields(record) for record in records))
        if forbidden:
            fail(f"{path}: contains redacted fields {sorted(forbidden)}")

        measured = [
            record
            for record in records
            if record.get("type") == "sample" and record.get("kind") == "measured"
        ]
        nonmeasured = [
            record
            for record in records
            if record.get("type") == "sample" and record.get("kind") != "measured"
        ]
        if len(measured) != specification["expected_measured_requests"]:
            fail(f"{path}: measured-request count mismatch")
        if len(nonmeasured) != specification["expected_nonmeasured_requests"]:
            fail(f"{path}: nonmeasured-request count mismatch")
        counts = Counter(record.get("target_tokens") for record in measured)
        expected_counts = {
            int(target): count for target, count in specification["expected_counts"].items()
        }
        if counts != expected_counts:
            fail(f"{path}: per-length request counts differ from the registry")
        if {record.get("mode") for record in measured} != {specification["mode"]}:
            fail(f"{path}: collection mode mismatch")

        repetitions: dict[int, list[int]] = defaultdict(list)
        schedule_rows: list[dict[str, Any]] = []
        for sequence, record in enumerate(measured, start=1):
            if record.get("session") != session_id:
                fail(f"{path}: sample session mismatch")
            if record.get("provider") != specification["provider"]:
                fail(f"{path}: provider mismatch")
            if record.get("model") != specification["api_model"]:
                fail(f"{path}: API model mismatch")
            if record.get("valid") is not True or record.get("status_code") != 200:
                fail(f"{path}: invalid measured request")
            if not 0 < record.get("ttft_ns", 0) <= record.get("total_ns", 0):
                fail(f"{path}: invalid timing interval")
            token_parts = sum(
                int(record.get(field) or 0)
                for field in ("new_input_tokens", "cache_read_tokens", "cache_write_tokens")
            )
            if token_parts != record.get("total_input_tokens"):
                fail(f"{path}: input-token accounting mismatch")
            for field in ("prompt_sha256", "stable_prefix_sha256", "cache_key_sha256"):
                validate_hash(record.get(field), path, field)

            repetition = int(record["repetition"])
            repetitions[repetition].append(int(record["target_tokens"]))
            block = repetition + 1
            schedule_rows.append(
                {
                    "sequence": sequence,
                    "block": block,
                    "target_tokens": record["target_tokens"],
                    "timestamp": record.get("timestamp", ""),
                    "request_started_at": record.get("request_started_at", ""),
                    "request_completed_at": record.get("request_completed_at", ""),
                }
            )

            observation = {
                "model": specification["model_label"],
                "provider": specification["provider"],
                "api_model": specification["api_model"],
                "session_id": session_id,
                "session_label": header.get("label", ""),
                "schema_version": record.get("schema_version", header.get("schema_version", "")),
                "design_status": specification["design_status"],
                "analysis_role": specification["analysis_role"],
                "mode": record.get("mode", ""),
                "sequence": sequence,
                "block": block,
                "repetition": repetition,
                "target_tokens": record.get("target_tokens", ""),
                "prepared_tokens": record.get("prepared_tokens", ""),
                "total_input_tokens": record.get("total_input_tokens", ""),
                "new_input_tokens": record.get("new_input_tokens", ""),
                "cache_read_tokens": record.get("cache_read_tokens", ""),
                "cache_write_tokens": record.get("cache_write_tokens", ""),
                "output_tokens": record.get("output_tokens", ""),
                "reasoning_tokens": record.get("reasoning_tokens", ""),
                "thinking_blocks": record.get("thinking_blocks", ""),
                "timestamp": record.get("timestamp", ""),
                "request_started_at": record.get("request_started_at", ""),
                "request_completed_at": record.get("request_completed_at", ""),
                "headers_seconds": seconds(record, "headers_ns"),
                "first_event_seconds": seconds(record, "first_event_ns"),
                "first_content_seconds": seconds(record, "first_content_ns"),
                "ttft_seconds": seconds(record, "ttft_ns"),
                "total_seconds": seconds(record, "total_ns"),
                "request_bytes": record.get("request_bytes", ""),
                "status_code": record.get("status_code", ""),
                "returned_model": record.get("returned_model", ""),
                "requested_service_tier": record.get("requested_service_tier", ""),
                "returned_service_tier": record.get("returned_service_tier", ""),
                "instruction_mode": record.get("instruction_mode", ""),
                "nonce_position": record.get("nonce_position", ""),
                "output_compliant": record.get("output_compliant", ""),
                "prompt_sha256": record.get("prompt_sha256", ""),
                "stable_prefix_sha256": record.get("stable_prefix_sha256", ""),
                "cache_key_sha256": record.get("cache_key_sha256", ""),
                "shared_cache_prefix_requested_tokens": record.get(
                    "shared_cache_prefix_requested_tokens", ""
                ),
                "estimated_cost_usd": record.get("estimated_cost_usd", ""),
            }
            observation_rows.append(
                {field: text_value(observation[field]) for field in OBSERVATION_FIELDS}
            )

        session_ends = [record for record in records if record.get("type") == "session_end"]
        complete = len(session_ends) == 1 and session_ends[0].get("status") == "complete"
        if specification["design_status"] == "complete_balanced" and not complete:
            fail(f"{path}: registry says complete but no complete session_end exists")
        if specification["design_status"] != "complete_balanced" and complete:
            fail(f"{path}: non-complete registry status conflicts with session_end")

        observed_lengths = sorted(counts)
        declared_lengths = header.get("lengths", [])
        per_length = ";".join(f"{target}:{counts[target]}" for target in observed_lengths)
        schedule_rel = Path("data/schedules/exploratory") / f"{session_id}.csv"
        raw_rel = Path("data/raw/exploratory") / path.name
        last_recorded_at = next(
            (timestamp_for(record) for record in reversed(records) if timestamp_for(record)),
            "",
        )
        manifest_rows.append(
            {
                "model": specification["model_label"],
                "provider": specification["provider"],
                "api_model": specification["api_model"],
                "session_id": session_id,
                "session_label": header.get("label", ""),
                "schema_version": header.get("schema_version", "legacy"),
                "design_status": specification["design_status"],
                "analysis_role": specification["analysis_role"],
                "mode": specification["mode"],
                "session_started_at": header.get("timestamp", ""),
                "last_recorded_at": last_recorded_at,
                "declared_context_lengths": ";".join(str(value) for value in declared_lengths),
                "observed_context_lengths": ";".join(str(value) for value in observed_lengths),
                "planned_repetitions": header.get("repetitions", ""),
                "observed_repetitions_by_length": per_length,
                "chronological_blocks": len(repetitions),
                "measured_requests": len(measured),
                "nonmeasured_requests": len(nonmeasured),
                "has_complete_session_end": str(complete).lower(),
                "has_request_boundaries": str(
                    all(
                        record.get("request_started_at")
                        and record.get("request_completed_at")
                        for record in measured
                    )
                ).lower(),
                "raw_file": raw_rel.as_posix(),
                "schedule_file": schedule_rel.as_posix(),
                "notes": specification["notes"],
            }
        )
        ttfts = [record["ttft_ns"] / 1_000_000_000 for record in measured]
        costs = [float(record.get("estimated_cost_usd") or 0) for record in measured]
        input_tokens = [int(record["total_input_tokens"]) for record in measured]
        summary_rows.append(
            {
                "model": specification["model_label"],
                "provider": specification["provider"],
                "session_id": session_id,
                "design_status": specification["design_status"],
                "mode": specification["mode"],
                "measured_requests": len(measured),
                "chronological_blocks": len(repetitions),
                "minimum_target_tokens": min(observed_lengths),
                "maximum_target_tokens": max(observed_lengths),
                "minimum_reported_input_tokens": min(input_tokens),
                "maximum_reported_input_tokens": max(input_tokens),
                "median_ttft_seconds": format(median(ttfts), ".9f"),
                "total_estimated_cost_usd": format(sum(costs), ".9f"),
            }
        )
        schedules[SCHEDULE_DIR / f"{session_id}.csv"] = csv_bytes(
            SCHEDULE_FIELDS, schedule_rows
        )

    exports = {
        MANIFEST_PATH: csv_bytes(MANIFEST_FIELDS, manifest_rows),
        OBSERVATIONS_PATH: csv_bytes(OBSERVATION_FIELDS, observation_rows),
        SUMMARY_PATH: csv_bytes(SUMMARY_FIELDS, summary_rows),
        **schedules,
    }
    return exports


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check",
        action="store_true",
        help="Validate the raw archive and require every derived CSV to be current",
    )
    args = parser.parse_args()
    exports = build_exports()
    if args.check:
        for path, expected in exports.items():
            if not path.exists():
                fail(f"missing generated file: {path.relative_to(ROOT)}")
            if path.read_bytes() != expected:
                fail(f"stale generated file: {path.relative_to(ROOT)}")
        print(
            "Validated 22 exploratory sessions, 303 measurements, "
            f"and {len(exports)} derived CSV files."
        )
        return

    for path, content in exports.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
    digest = hashlib.sha256(OBSERVATIONS_PATH.read_bytes()).hexdigest()
    print(f"Exported 303 exploratory measurements (CSV SHA-256 {digest}).")


if __name__ == "__main__":
    main()
