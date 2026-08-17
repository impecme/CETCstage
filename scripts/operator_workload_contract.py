"""Semantic workload checks for operator performance reports.

``input_elements`` is a common scale metadata field, but it is not the
correct report sample count for every operator.  This module keeps the small
set of operators whose performance workload has an explicit semantic size in
one place so a baseline collector cannot freeze a silently mismatched run.
"""

from __future__ import annotations

from collections.abc import Mapping
from typing import Any


class WorkloadContractError(ValueError):
    """Raised when a manifest omits a required scale-sensitive field."""


def _positive_int(case: Mapping[str, Any], field: str, operator: str) -> int:
    value = case.get(field)
    if isinstance(value, bool) or value is None:
        raise WorkloadContractError(f"{operator}: missing {field}")
    try:
        result = int(value)
    except (TypeError, ValueError) as exc:
        raise WorkloadContractError(f"{operator}: invalid {field}={value!r}") from exc
    if result <= 0:
        raise WorkloadContractError(f"{operator}: {field} must be positive, got {result}")
    return result


def expected_perf_samples(operator: str, case: Mapping[str, Any]) -> int | None:
    """Return the semantic ``CaseReport.samples`` value for known operators.

    ``None`` means the operator has no special report-size contract here; its
    existing output-shape logic remains authoritative.
    """

    if operator == "filter_design/cmplx_sort":
        return _positive_int(case, "sample_count", operator)
    if operator in {"filter_design/kaiser_beta", "filter_design/kaiser_atten"}:
        return 1
    if operator in {"filtering/firfilter_zi", "filtering/lfilter_zi"}:
        return _positive_int(case, "filter_order", operator)
    if operator == "radartools/cfar_alpha":
        return 1
    if operator == "wavelets/qmf":
        return _positive_int(case, "hk_count", operator)
    if operator in {"wavelets/morlet", "wavelets/ricker", "wavelets/morlet2"}:
        return _positive_int(case, "points", operator)
    if operator == "wavelets/cwt":
        data_count = _positive_int(case, "data_count", operator)
        widths_count = _positive_int(case, "widths_count", operator)
        return data_count * widths_count
    return None


def validate_perf_report(
    operator: str,
    manifest: Mapping[str, Any],
    payload: Mapping[str, Any],
) -> list[str]:
    """Validate known semantic sample counts in one emitted metrics report."""

    manifest_cases = manifest.get("perf_cases", [])
    reported_cases = {
        item.get("case_id"): item
        for item in payload.get("cases", [])
        if item.get("category") == "perf"
    }
    errors: list[str] = []
    for manifest_case in manifest_cases:
        case_id = manifest_case.get("id")
        if not case_id:
            errors.append(f"{operator}: perf case has no id")
            continue
        try:
            expected = expected_perf_samples(operator, manifest_case)
        except WorkloadContractError as exc:
            errors.append(str(exc))
            continue
        if expected is None:
            continue
        report_case = reported_cases.get(case_id)
        if report_case is None:
            errors.append(f"{operator}/{case_id}: missing perf report case")
            continue
        actual = report_case.get("samples")
        try:
            actual_int = int(actual)
        except (TypeError, ValueError):
            errors.append(f"{operator}/{case_id}: invalid report samples={actual!r}")
            continue
        if actual_int != expected:
            errors.append(
                f"{operator}/{case_id}: report samples={actual_int}, expected {expected}"
            )
    return errors

