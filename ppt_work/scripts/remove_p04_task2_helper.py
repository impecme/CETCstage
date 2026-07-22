#!/usr/bin/env python3
"""Remove the Task2 private-helper block from P04 of the final contest deck.

P04 is an editable PPT slide with the architecture diagram embedded as a
raster layer.  A white native PowerPoint rectangle masks only the helper box
and its outgoing connector, preserving the CPU/GPU dual-backend diagram.
The script is idempotent and overwrites the requested PPTX in place.
"""

from __future__ import annotations

import argparse
import tempfile
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET


P = "http://schemas.openxmlformats.org/presentationml/2006/main"
A = "http://schemas.openxmlformats.org/drawingml/2006/main"
NS = {"p": P, "a": A}
for prefix, uri in NS.items():
    ET.register_namespace(prefix, uri)

SLIDE_XML = "ppt/slides/slide4.xml"
SHAPE_NAME = "P04_mask_task2_private_helper"

# EMU coordinates were derived from the embedded architecture raster's crop
# and cover only its helper box plus the connector from src/zhongkexin.
MASK = {"x": "6000000", "y": "4500000", "cx": "1700000", "cy": "900000"}


def tag(prefix: str, local: str) -> str:
    return f"{{{NS[prefix]}}}{local}"


def shape_name(element: ET.Element) -> str | None:
    node = element.find(".//p:cNvPr", NS)
    return None if node is None else node.attrib.get("name")


def max_shape_id(tree: ET.Element) -> int:
    ids = []
    for node in tree.findall(".//p:cNvPr", NS):
        try:
            ids.append(int(node.attrib.get("id", "0")))
        except ValueError:
            pass
    return max(ids, default=1)


def make_mask(shape_id: int) -> ET.Element:
    shape = ET.Element(tag("p", "sp"))
    nv = ET.SubElement(shape, tag("p", "nvSpPr"))
    ET.SubElement(nv, tag("p", "cNvPr"), {"id": str(shape_id), "name": SHAPE_NAME})
    ET.SubElement(nv, tag("p", "cNvSpPr"))
    ET.SubElement(nv, tag("p", "nvPr"))

    props = ET.SubElement(shape, tag("p", "spPr"))
    transform = ET.SubElement(props, tag("a", "xfrm"))
    ET.SubElement(transform, tag("a", "off"), {"x": MASK["x"], "y": MASK["y"]})
    ET.SubElement(transform, tag("a", "ext"), {"cx": MASK["cx"], "cy": MASK["cy"]})
    geometry = ET.SubElement(props, tag("a", "prstGeom"), {"prst": "rect"})
    ET.SubElement(geometry, tag("a", "avLst"))
    fill = ET.SubElement(props, tag("a", "solidFill"))
    ET.SubElement(fill, tag("a", "srgbClr"), {"val": "FFFFFF"})
    line = ET.SubElement(props, tag("a", "ln"))
    ET.SubElement(line, tag("a", "noFill"))
    return shape


def update_deck(path: Path) -> None:
    with zipfile.ZipFile(path) as source:
        slide = ET.fromstring(source.read(SLIDE_XML))
        tree = slide.find(".//p:spTree", NS)
        if tree is None:
            raise ValueError(f"{SLIDE_XML} has no shape tree")

        for child in list(tree):
            if shape_name(child) == SHAPE_NAME:
                tree.remove(child)
        tree.append(make_mask(max_shape_id(tree) + 1))

        replacement = ET.tostring(slide, encoding="utf-8", xml_declaration=True)
        with tempfile.NamedTemporaryFile(dir=path.parent, suffix=".pptx", delete=False) as tmp:
            temp_path = Path(tmp.name)
        try:
            with zipfile.ZipFile(temp_path, "w", zipfile.ZIP_DEFLATED) as target:
                for name in source.namelist():
                    target.writestr(name, replacement if name == SLIDE_XML else source.read(name))
            temp_path.replace(path)
        finally:
            temp_path.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "deck",
        nargs="?",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "CICC1001212_中科芯_分赛区总决赛_答辩PPT.pptx",
        help="Final PPTX to update in place.",
    )
    args = parser.parse_args()
    update_deck(args.deck.resolve())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
