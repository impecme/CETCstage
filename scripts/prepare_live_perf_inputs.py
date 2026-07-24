#!/usr/bin/env python3
"""Prepare temporary reduced-size performance manifests for the live demo.

The source ``data/generated/unit`` manifests remain untouched.  Only the
``perf_cases`` in a disposable output tree are reduced; accuracy cases are not
copied or used.  The resulting inputs retain each operator's performance code
path while lowering the CPU/GPU workload enough for a short presentation.
"""

from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT / "data/generated/unit")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--operator-set", default="core53")
    parser.add_argument("--scale-divisor", type=int, default=16)
    args = parser.parse_args()
    if args.scale_divisor < 2:
        parser.error("--scale-divisor must be >= 2")
    return args


def load_operator_set(name: str) -> list[str]:
    payload = json.loads((ROOT / "tests/contracts/operator_sets.json").read_text(encoding="utf-8"))
    sets = payload.get("sets", {})
    all81 = sets.get("all81", {}).get("operators", [])
    if not isinstance(all81, list) or not all(isinstance(key, str) for key in all81):
        raise RuntimeError("operator_sets.json all81 is invalid")

    def resolve(current: str, stack: set[str]) -> list[str]:
        if current in stack:
            raise RuntimeError(f"cyclic operator set: {current}")
        item = sets.get(current)
        if not isinstance(item, dict):
            raise RuntimeError(f"unknown operator set: {current}")
        if "operators" in item:
            operators = item["operators"]
            if not isinstance(operators, list) or not all(isinstance(key, str) for key in operators):
                raise RuntimeError(f"invalid operator list: {current}")
            return list(operators)
        included: set[str] = set()
        for child in item.get("include_sets", []):
            included.update(resolve(child, stack | {current}))
        excluded: set[str] = set()
        for child in item.get("exclude_sets", []):
            excluded.update(resolve(child, stack | {current}))
        return [key for key in all81 if key in included and key not in excluded]

    return resolve(name, set())


def reduce_count(value: Any, divisor: int, minimum: int = 1) -> Any:
    if not isinstance(value, int) or isinstance(value, bool):
        return value
    return max(minimum, value // divisor)


def reduce_shape(shape: Any, divisor: int) -> Any:
    if not isinstance(shape, list) or not all(isinstance(item, int) and not isinstance(item, bool) for item in shape):
        return shape
    if len(shape) == 1:
        return [reduce_count(shape[0], divisor)]
    if len(shape) == 2:
        side_divisor = 1
        while side_divisor * side_divisor < divisor:
            side_divisor += 1
        return [reduce_count(shape[0], side_divisor), reduce_count(shape[1], side_divisor)]
    return [reduce_count(item, divisor) for item in shape]


def reduce_generator(generator: dict[str, Any], divisor: int) -> None:
    # Generator fields describe the performance input itself.  Filter/window
    # parameters are deliberately not changed.
    if "count" in generator:
        generator["count"] = reduce_count(generator["count"], divisor)
    if "shape" in generator:
        generator["shape"] = reduce_shape(generator["shape"], divisor)


def reduce_perf_case(case: dict[str, Any], divisor: int) -> dict[str, Any]:
    reduced = json.loads(json.dumps(case))

    for key in ("size", "x_count", "data_count", "hk_count", "points"):
        if key in reduced:
            reduced[key] = reduce_count(reduced[key], divisor)

    # ``num`` is an output sample count.  Keeping the original ratio avoids
    # changing the resampling route while reducing CPU/GPU work.
    if "num" in reduced:
        reduced["num"] = reduce_count(reduced["num"], divisor)

    for key in ("x_shape", "data_shape", "shape", "shape1"):
        if key in reduced:
            reduced[key] = reduce_shape(reduced[key], divisor)

    for key, value in reduced.items():
        if key.endswith("_generator") and isinstance(value, dict):
            reduce_generator(value, divisor)

    # FFT lengths, filter taps, window parameters, guard/reference windows and
    # correlation kernels remain fixed.  For radar matrices the second axis is
    # the fixed FFT/template axis, so only reduce the pulse dimension.
    if reduced.get("id") == "perf_large" and isinstance(reduced.get("x_shape"), list):
        x_shape = case.get("x_shape")
        if x_shape == [4096, 256]:
            reduced["x_shape"] = [reduce_count(4096, divisor), 256]
            x_generator = reduced.get("x_generator")
            if isinstance(x_generator, dict):
                x_generator["shape"] = list(reduced["x_shape"])

    # ambgfun uses a generated one-dimensional signal whose generator length
    # must match x_shape.  Template lengths in pulse-compression remain fixed.
    x_generator = reduced.get("x_generator")
    x_shape = reduced.get("x_shape")
    if isinstance(x_generator, dict) and isinstance(x_shape, list) and len(x_shape) == 1:
        original_x_shape = case.get("x_shape")
        if original_x_shape == [case.get("x_generator", {}).get("length")]:
            x_generator["length"] = x_shape[0]

    return reduced


def main() -> int:
    args = parse_args()
    source = args.source.resolve()
    output = args.output.resolve()
    if not source.is_dir():
        raise RuntimeError(f"source directory not found: {source}")
    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)

    operators = load_operator_set(args.operator_set)
    prepared = 0
    for key in operators:
        manifest = source / key / "manifest.json"
        if not manifest.is_file():
            raise RuntimeError(f"missing manifest: {manifest}")
        payload = json.loads(manifest.read_text(encoding="utf-8"))
        cases = payload.get("perf_cases")
        if not isinstance(cases, list) or not all(isinstance(case, dict) for case in cases):
            raise RuntimeError(f"invalid perf_cases: {manifest}")
        # One representative performance input per operator is sufficient for
        # the live run.  The normal benchmark keeps every declared perf case.
        payload["perf_cases"] = [reduce_perf_case(case, args.scale_divisor) for case in cases[:1]]
        target = output / key / "manifest.json"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        prepared += 1

    print(
        f"[live-perf-inputs] prepared {prepared} temporary performance manifests "
        f"(workload scale: approximately 1/{args.scale_divisor})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
