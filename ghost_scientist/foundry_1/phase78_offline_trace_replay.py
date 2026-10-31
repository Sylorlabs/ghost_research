#!/usr/bin/env python3
"""Recompute the pinned production trace with two local independent parsers."""

from __future__ import annotations

import csv
import hashlib
import io
import json
import math
import pathlib
from collections import Counter
from collections.abc import Iterable, Iterator, Sequence


HERE = pathlib.Path(__file__).resolve().parent
TRACE = HERE / "external_traces/source/alibaba_lora_request_trace.csv"
PROTOCOL = HERE / "external_traces/OFFLINE_REPLAY_PROTOCOL_V1.json"
CONNECTOR_AGGREGATE = (
    HERE / "external_traces/INVOCATION_TRACE_AGGREGATE_V1.json"
)
RESULT = HERE / "results/phase78_offline_trace_replay.json"


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def byte_csv_rows(raw: bytes) -> Iterator[list[str]]:
    row: list[str] = []
    field = bytearray()
    quoted = False
    index = 0
    while index < len(raw):
        byte = raw[index]
        if byte == 34:
            if quoted and index + 1 < len(raw) and raw[index + 1] == 34:
                field.append(34)
                index += 2
                continue
            quoted = not quoted
        elif byte == 44 and not quoted:
            row.append(field.decode("utf-8"))
            field.clear()
        elif byte == 10 and not quoted:
            row.append(field.decode("utf-8").removesuffix("\r"))
            field.clear()
            yield row
            row = []
        else:
            field.append(byte)
        index += 1
    if quoted:
        raise ValueError("unterminated quoted field")
    if field or row:
        row.append(field.decode("utf-8").removesuffix("\r"))
        yield row


def nearest_rank(values: Sequence[int], quantile: float) -> int:
    return values[max(0, math.ceil(quantile * len(values)) - 1)]


def summarize(rows: Iterable[list[str]]) -> dict:
    iterator = iter(rows)
    header = next(iterator)
    columns = {name: index for index, name in enumerate(header)}
    required = {
        "gmt_create",
        "predict_status",
        "checkpoint_model_version_id",
    }
    if not required.issubset(columns):
        raise ValueError("required trace columns missing")
    statuses: Counter[str] = Counter()
    models: dict[str, int] = {}
    empty_model_rows = 0
    malformed_rows = 0
    data_rows = 0
    timestamp_min: str | None = None
    timestamp_max: str | None = None
    for row in iterator:
        data_rows += 1
        if len(row) != len(header):
            malformed_rows += 1
            continue
        timestamp = row[columns["gmt_create"]]
        timestamp_min = (
            timestamp
            if timestamp_min is None or timestamp < timestamp_min
            else timestamp_min
        )
        timestamp_max = (
            timestamp
            if timestamp_max is None or timestamp > timestamp_max
            else timestamp_max
        )
        status = row[columns["predict_status"]]
        statuses[status] += 1
        model = row[columns["checkpoint_model_version_id"]]
        if not model:
            empty_model_rows += 1
            continue
        models.setdefault(model, 0)
        if status == "SUCCEED":
            models[model] += 1
    counts = sorted(models.values())
    return {
        "header": header,
        "data_rows": data_rows,
        "malformed_rows": malformed_rows,
        "timestamp_min": timestamp_min,
        "timestamp_max": timestamp_max,
        "status_counts": dict(sorted(statuses.items())),
        "empty_model_rows": empty_model_rows,
        "nonempty_model_identities": len(models),
        "zero_success_model_identities": sum(value == 0 for value in counts),
        "successful_requests_per_model": {
            "minimum": counts[0],
            "q10_nearest_rank": nearest_rank(counts, 0.10),
            "q25_nearest_rank": nearest_rank(counts, 0.25),
            "median_nearest_rank": nearest_rank(counts, 0.50),
            "q75_nearest_rank": nearest_rank(counts, 0.75),
            "q90_nearest_rank": nearest_rank(counts, 0.90),
            "maximum": counts[-1],
            "sum": sum(counts),
        },
        "N_star_reference": nearest_rank(counts, 0.25),
    }


def connector_shape(aggregate: dict) -> dict:
    parse = aggregate["parse"]
    return {
        "header": parse["header"],
        "data_rows": parse["data_rows"],
        "malformed_rows": parse["bad_width_rows"],
        "timestamp_min": parse["timestamp_min"],
        "timestamp_max": parse["timestamp_max"],
        "status_counts": dict(sorted(parse["status_counts"].items())),
        "empty_model_rows": parse["empty_model_rows"],
        "nonempty_model_identities": parse["nonempty_model_identities"],
        "zero_success_model_identities": parse[
            "zero_success_model_identities"
        ],
        "successful_requests_per_model": aggregate[
            "successful_requests_per_model"
        ],
        "N_star_reference": aggregate["predeclared_result"][
            "N_star_external_reference"
        ],
    }


def run() -> None:
    protocol = json.loads(PROTOCOL.read_text(encoding="utf-8"))
    aggregate = json.loads(CONNECTOR_AGGREGATE.read_text(encoding="utf-8"))
    raw = TRACE.read_bytes()
    stdlib = summarize(
        csv.reader(io.StringIO(raw.decode("utf-8"), newline=""))
    )
    independent = summarize(byte_csv_rows(raw))
    expected = connector_shape(aggregate)
    checks = {
        "protocol_frozen": protocol["frozen_before_offline_replay"],
        "local_sha256_exact": (
            hashlib.sha256(raw).hexdigest()
            == protocol["input"]["sha256"]
        ),
        "stdlib_matches_independent": stdlib == independent,
        "stdlib_matches_connector": stdlib == expected,
        "independent_matches_connector": independent == expected,
        "rows_exact": stdlib["data_rows"] == 26823,
        "models_exact": stdlib["nonempty_model_identities"] == 86,
        "successes_exact": (
            stdlib["successful_requests_per_model"]["sum"] == 26392
        ),
        "N_star_exact": stdlib["N_star_reference"] == 3,
        "validation_v6_access_forbidden": (
            protocol["validation_v6_access_allowed"] is False
        ),
    }
    if not all(checks.values()):
        raise RuntimeError("offline trace replay failed")
    payload = {
        "version": "FOUNDRY_OFFLINE_TRACE_REPLAY_V1",
        "status": "OFFLINE_TRACE_REPLAY_PASS",
        "checks": checks,
        "stdlib_parser": stdlib,
        "independent_byte_parser": independent,
        "connector_receipt": expected,
        "exact_parser_relations": 3,
        "P2": {
            "source_bytes_locally_frozen": True,
            "two_offline_parsers_pass": True,
            "connector_receipt_reproduced": True,
            "horizon_unit_mapping_validated": False,
            "complete": False,
        },
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE78_OFFLINE_TRACE_REPLAY"
        f" status={payload['status']}"
        " parsers=2/2 connector=PASS"
        f" rows={stdlib['data_rows']}"
        f" models={stdlib['nonempty_model_identities']}"
        f" N_reference={stdlib['N_star_reference']}"
        " P2=false prospective=false"
    )


if __name__ == "__main__":
    run()
