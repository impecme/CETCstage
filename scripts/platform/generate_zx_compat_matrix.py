#!/usr/bin/env python3

"""Generate a traceable ZQ500 compatibility matrix from the rematch XLSX files."""

from __future__ import annotations

import argparse
import csv
import json
import posixpath
import re
import xml.etree.ElementTree as ET
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any
from zipfile import ZipFile


MAIN_NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
REL_NS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
PACKAGE_REL_NS = "http://schemas.openxmlformats.org/package/2006/relationships"
NS = {"m": MAIN_NS, "r": REL_NS, "p": PACKAGE_REL_NS}
API_PATTERN = re.compile(
    r"\b(?:cuda|cu(?:blas|fft|dnn|solver|sparse|rand)?)[A-Z][A-Za-z0-9_]*"
)
DANGEROUS_PATTERN = re.compile(
    r"(?:Reset|Peer|IPC|External|Graphics|NvSci|Import|Export)", re.IGNORECASE
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--driver", required=True)
    parser.add_argument("--runtime", required=True)
    parser.add_argument("--libraries", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--summary-markdown")
    return parser.parse_args()


def column_index(reference: str) -> int:
    letters = "".join(character for character in reference if character.isalpha())
    value = 0
    for character in letters.upper():
        value = value * 26 + ord(character) - ord("A") + 1
    return max(value - 1, 0)


def shared_strings(archive: ZipFile) -> list[str]:
    if "xl/sharedStrings.xml" not in archive.namelist():
        return []
    root = ET.fromstring(archive.read("xl/sharedStrings.xml"))
    return [
        "".join(node.text or "" for node in item.iterfind(".//m:t", NS))
        for item in root.findall("m:si", NS)
    ]


def cell_text(cell: ET.Element, strings: list[str]) -> str:
    cell_type = cell.attrib.get("t", "")
    if cell_type == "inlineStr":
        return "".join(node.text or "" for node in cell.iterfind(".//m:t", NS)).strip()
    value = cell.find("m:v", NS)
    if value is None or value.text is None:
        return ""
    raw = value.text
    if cell_type == "s":
        return strings[int(raw)].strip()
    if cell_type == "b":
        return "true" if raw == "1" else "false"
    return raw.strip()


def workbook_rows(path: Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    with ZipFile(path) as archive:
        strings = shared_strings(archive)
        workbook = ET.fromstring(archive.read("xl/workbook.xml"))
        relationships = ET.fromstring(archive.read("xl/_rels/workbook.xml.rels"))
        targets = {
            item.attrib["Id"]: item.attrib["Target"]
            for item in relationships.findall("p:Relationship", NS)
        }
        sheets = workbook.find("m:sheets", NS)
        if sheets is None:
            raise ValueError(f"workbook has no sheets: {path}")
        for sheet in sheets:
            sheet_name = sheet.attrib["name"]
            relation_id = sheet.attrib[f"{{{REL_NS}}}id"]
            target = targets[relation_id]
            sheet_path = posixpath.normpath(
                target if target.startswith("xl/") else posixpath.join("xl", target)
            )
            root = ET.fromstring(archive.read(sheet_path))
            for row in root.findall(".//m:sheetData/m:row", NS):
                indexed: dict[int, str] = {}
                for cell in row.findall("m:c", NS):
                    text = cell_text(cell, strings)
                    if text:
                        indexed[column_index(cell.attrib.get("r", "A1"))] = text
                if not indexed:
                    continue
                width = max(indexed) + 1
                cells = [indexed.get(index, "") for index in range(width)]
                records.append(
                    {
                        "source_file": path.name,
                        "sheet": sheet_name,
                        "source_row": int(row.attrib.get("r", "0")),
                        "cells": cells,
                    }
                )
    return records


def normalize_status(cells: list[str], source_kind: str, has_api: bool) -> str:
    text = " | ".join(cells)
    lowered = text.lower()
    if "无此类api" in lowered or "not applicable" in lowered:
        return "not_applicable"
    if "part supported" in lowered or "部分支持" in lowered:
        return "partial"
    # The CUDA API workbooks place the authoritative API status in the last
    # column. Looking for standalone N/Y in the full signature confuses common
    # parameter names (for example, size_t N) with support markers.
    if source_kind in {"driver", "runtime"} and has_api and cells:
        status_cell = cells[-1].strip().lower()
        if status_cell == "unsupported":
            return "unsupported"
        if status_cell.startswith("part supported"):
            return "partial"
        if status_cell.startswith("supported"):
            return "partial" if "仅支持" in cells[-1] else "supported"
    if "unsupported" in lowered or "不支持" in lowered:
        # Scientific-library notes describe unsupported data types or argument
        # variants. The API remains available, so these are support boundaries.
        return "partial" if source_kind == "libraries" and has_api else "unsupported"
    if "supported" in lowered or "支持" in lowered:
        restriction_words = ("仅", "限制", "必须", "无效", "不完整")
        return "partial" if any(word in text for word in restriction_words) else "supported"
    if source_kind == "libraries" and has_api:
        return "supported"
    return "documented"


def classify_rows(records: list[dict[str, Any]], source_kind: str) -> list[dict[str, Any]]:
    output = []
    carried_module: dict[str, str] = {}
    for record in records:
        cells = record["cells"]
        full_text = " | ".join(value.replace("\n", " ").strip() for value in cells if value.strip())
        api_names = list(dict.fromkeys(API_PATTERN.findall(full_text)))
        first = cells[0].strip() if cells else ""
        second = cells[1].strip() if len(cells) > 1 else ""
        sheet = record["sheet"]
        if first and first not in {"Modules", "API列表"} and not API_PATTERN.search(first):
            carried_module[sheet] = first.replace("\n", " ")
        module = sheet if source_kind == "libraries" else carried_module.get(sheet, first)

        header_tokens = {"Modules", "API", "API列表", "功能", "功能说明", "备注"}
        if any(value.strip() in header_tokens for value in cells):
            row_kind = "header"
        elif api_names:
            row_kind = "api"
        elif len([value for value in cells if value.strip()]) <= 2:
            row_kind = "category"
        else:
            row_kind = "note"

        status = normalize_status(cells, source_kind, bool(api_names))
        api_label = ",".join(api_names)
        if row_kind == "api" and not api_label:
            api_label = second or first
        restriction = " | ".join(value.replace("\n", " ").strip() for value in cells[2:] if value.strip())
        if row_kind != "api":
            probe_mode = "none"
        elif status == "unsupported":
            probe_mode = "forbidden_scan"
        elif any(DANGEROUS_PATTERN.search(name) for name in api_names):
            probe_mode = "compile_only"
        else:
            probe_mode = "runtime_pending"

        output.append(
            {
                **record,
                "source_kind": source_kind,
                "row_kind": row_kind,
                "module": module,
                "api": api_label,
                "api_names": api_names,
                "support": status,
                "restriction": restriction,
                "probe_mode": probe_mode,
                "probe_status": "not_applicable" if probe_mode == "none" else "pending",
                "source_text": full_text,
            }
        )
    return output


def forbidden_api_names(row: dict[str, Any]) -> set[str]:
    if row["row_kind"] != "api":
        return set()
    if row["support"] == "unsupported":
        return set(row["api_names"])
    if row["support"] != "partial":
        return set()
    if len(row["api_names"]) <= 1:
        return set()

    # Mixed scientific-library rows can list supported and unsupported APIs in
    # one cell. Only names in an explicit unsupported clause are forbidden.
    forbidden = set()
    for clause in re.split(r"[，,；;。]", row["source_text"]):
        if "不支持" in clause or "unsupported" in clause.lower():
            forbidden.update(API_PATTERN.findall(clause))
    return forbidden


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    fields = (
        "source_kind", "source_file", "sheet", "source_row", "row_kind", "module",
        "api", "support", "restriction", "probe_mode", "probe_status", "source_text",
    )
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for row in rows:
            writer.writerow({field: row.get(field, "") for field in fields})


def markdown_escape(value: Any) -> str:
    return str(value).replace("|", "\\|").replace("\n", " ")


def write_markdown(path: Path, rows: list[dict[str, Any]], summary: dict[str, Any]) -> None:
    lines = [
        "# ZQ500 CUDA 11.7 与科学计算库兼容矩阵",
        "",
        f"- status: `{summary['status']}`",
        f"- source rows: `{summary['source_row_count']}`",
        f"- API rows: `{summary['api_row_count']}`",
        f"- unique APIs: `{summary['unique_api_count']}`",
        f"- forbidden APIs: `{summary['forbidden_api_count']}`",
        "",
        "| 来源 | sheet/row | 类别 | 模块 | API | 支持状态 | 限制 | 探针 |",
        "| --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for row in rows:
        lines.append(
            f"| {markdown_escape(row['source_kind'])} | "
            f"{markdown_escape(row['sheet'])}/{row['source_row']} | {row['row_kind']} | "
            f"{markdown_escape(row['module'])} | {markdown_escape(row['api'] or '-')} | "
            f"{row['support']} | {markdown_escape(row['restriction'] or '-')} | "
            f"{row['probe_mode']}:{row['probe_status']} |"
        )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_summary_markdown(path: Path, summary: dict[str, Any]) -> None:
    lines = [
        "# ZQ500 平台兼容矩阵摘要",
        "",
        "本文件由 `scripts/platform/generate_zx_compat_matrix.py` 从三个复赛 XLSX 表生成。",
        "完整逐行矩阵位于 `data/reports/zhongkexin/v5_2_compatibility/`。",
        "",
        "## 覆盖结果",
        "",
        f"- 非空源行：`{summary['source_row_count']}`。",
        f"- API 行：`{summary['api_row_count']}`。",
        f"- 唯一 API：`{summary['unique_api_count']}`。",
        f"- 明确禁止 API：`{summary['forbidden_api_count']}`。",
        f"- Driver/Runtime/科学库源行：`{summary['source_counts']['driver']}` / "
        f"`{summary['source_counts']['runtime']}` / `{summary['source_counts']['libraries']}`。",
        "",
        "## 状态口径",
        "",
        "- `supported`：进入安全运行探针。",
        "- `partial`：记录限制并在边界探针中验证。",
        "- `unsupported`：API 行进入项目禁止引用扫描。",
        "- 设备复位、跨设备、IPC、外部资源等高影响 API 仅编译验证。",
        "- 科学库某数据类型或参数形态不支持时，整行记为 `partial`；只有明确点名的不可用 API 才进入禁止清单。",
        "",
        "本摘要仅证明源表解析和分类完成。探针状态将在 V5.2-06 更新，不代表当前项目已通过全部兼容性验证。",
    ]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    args = parse_args()
    sources = (
        ("driver", Path(args.driver)),
        ("runtime", Path(args.runtime)),
        ("libraries", Path(args.libraries)),
    )
    rows = []
    source_counts = {}
    for source_kind, path in sources:
        if not path.is_file():
            raise FileNotFoundError(path)
        source_rows = classify_rows(workbook_rows(path), source_kind)
        if not source_rows:
            raise ValueError(f"no non-empty rows parsed from {path}")
        source_counts[source_kind] = len(source_rows)
        rows.extend(source_rows)

    unique_apis = sorted({name for row in rows for name in row["api_names"]})
    forbidden_apis = sorted({name for row in rows for name in forbidden_api_names(row)})
    summary = {
        "status": "passed",
        "source_row_count": len(rows),
        "api_row_count": sum(row["row_kind"] == "api" for row in rows),
        "unique_api_count": len(unique_apis),
        "forbidden_api_count": len(forbidden_apis),
        "source_counts": source_counts,
        "support_counts": dict(sorted(Counter(row["support"] for row in rows).items())),
        "row_kind_counts": dict(sorted(Counter(row["row_kind"] for row in rows).items())),
        "probe_mode_counts": dict(sorted(Counter(row["probe_mode"] for row in rows).items())),
    }
    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    write_csv(output / "compatibility.csv", rows)
    (output / "compatibility.json").write_text(
        json.dumps({"summary": summary, "rows": rows}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    write_markdown(output / "compatibility.md", rows, summary)
    (output / "forbidden_apis.txt").write_text(
        "".join(f"{name}\n" for name in forbidden_apis), encoding="utf-8"
    )
    (output / "summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    if args.summary_markdown:
        write_summary_markdown(Path(args.summary_markdown), summary)
    print(json.dumps(summary, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
