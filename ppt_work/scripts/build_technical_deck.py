#!/usr/bin/env python3
"""Build the P03-P19 technical-section PPTX from approved full-slide PNGs.

The two example decks are only visual references.  The 17-slide CICC deck is
used here as an OOXML container: every slide-level object is replaced by one
approved project image.  P01, P02 and P20 are deliberately excluded because
the team will create them itself.
"""

from __future__ import annotations

import argparse
import re
import sys
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET


SLIDES = (
    "P03_赛题重述_整页_v03_技术链路.png",
    "P04_技术路线_统一L6实测_v07.png",
    "P05_Wiener_Tile_Halo_整页_v01.png",
    "P06_IIR_Affine_Prefix_Scan_整页_v01.png",
    "P07_Periodogram_R2C_Fusion_Cache_整页_v01.png",
    "P08_Task1_Device_Resident_整页_v01.png",
    "P09_Task1_统一L1-L6_实测_v07.png",
    "P10_Task2_Score_Only_生图重构_v06.png",
    "P11_Task2_统一L1-L6_实测_v07.png",
    "P12_代码架构_整页_v01.png",
    "P13_81算子与公共机制_整页_v01.png",
    "P14_统一L6正确性_实测_v07.png",
    "P15_算子库性能总览_整页_v02.png",
    "P16_统一L1-L6规模与热点_实测_v07.png",
    "P17_统一测评与改进方向_生图重构_v06.png",
    "P18_核心亮点_生图重构_v06.png",
    "P19_AI工具使用说明_生图重构_v06.png",
)

P = "http://schemas.openxmlformats.org/presentationml/2006/main"
A = "http://schemas.openxmlformats.org/drawingml/2006/main"
R = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
PKG_R = "http://schemas.openxmlformats.org/package/2006/relationships"
CT = "http://schemas.openxmlformats.org/package/2006/content-types"
NS = {"p": P, "a": A, "r": R, "rel": PKG_R, "ct": CT}
for prefix, uri in (("p", P), ("a", A), ("r", R)):
    ET.register_namespace(prefix, uri)

# PowerPoint widescreen 13.333 × 7.5 inches, in English Metric Units.
SLIDE_CX = 12_192_000
SLIDE_CY = 6_858_000


def xml_tag(prefix: str, name: str) -> str:
    return f"{{{NS[prefix]}}}{name}"


def ordered_slide_names(names: list[str]) -> list[str]:
    return sorted(
        names,
        key=lambda name: int(re.search(r"slide(\d+)\.xml$", name).group(1)),
    )


def set_widescreen(presentation: bytes) -> bytes:
    root = ET.fromstring(presentation)
    size = root.find("p:sldSz", NS)
    if size is None:
        size = ET.SubElement(root, xml_tag("p", "sldSz"))
    size.attrib.update({"cx": str(SLIDE_CX), "cy": str(SLIDE_CY), "type": "screen16x9"})
    return ET.tostring(root, encoding="utf-8", xml_declaration=True)


def one_full_bleed_picture(slide: bytes, label: str) -> bytes:
    root = ET.fromstring(slide)
    tree = root.find(".//p:cSld/p:spTree", NS)
    if tree is None:
        raise ValueError("slide has no spTree")

    # Keep the group-shape properties required by DrawingML; remove all slide
    # content inherited from the example deck.
    for child in list(tree)[2:]:
        tree.remove(child)

    pic = ET.SubElement(tree, xml_tag("p", "pic"))
    nv = ET.SubElement(pic, xml_tag("p", "nvPicPr"))
    ET.SubElement(nv, xml_tag("p", "cNvPr"), {"id": "2", "name": label})
    ET.SubElement(nv, xml_tag("p", "cNvPicPr"))
    ET.SubElement(nv, xml_tag("p", "nvPr"))

    fill = ET.SubElement(pic, xml_tag("p", "blipFill"))
    ET.SubElement(fill, xml_tag("a", "blip"), {xml_tag("r", "embed"): "rIdTechnicalImage"})
    stretch = ET.SubElement(fill, xml_tag("a", "stretch"))
    ET.SubElement(stretch, xml_tag("a", "fillRect"))

    props = ET.SubElement(pic, xml_tag("p", "spPr"))
    transform = ET.SubElement(props, xml_tag("a", "xfrm"))
    ET.SubElement(transform, xml_tag("a", "off"), {"x": "0", "y": "0"})
    ET.SubElement(transform, xml_tag("a", "ext"), {"cx": str(SLIDE_CX), "cy": str(SLIDE_CY)})
    geometry = ET.SubElement(props, xml_tag("a", "prstGeom"), {"prst": "rect"})
    ET.SubElement(geometry, xml_tag("a", "avLst"))
    return ET.tostring(root, encoding="utf-8", xml_declaration=True)


def add_image_relation(rels: bytes, target: str) -> bytes:
    root = ET.fromstring(rels)
    for relation in list(root):
        if relation.attrib.get("Id") == "rIdTechnicalImage":
            root.remove(relation)
    ET.SubElement(
        root,
        xml_tag("rel", "Relationship"),
        {
            "Id": "rIdTechnicalImage",
            "Type": "http://schemas.openxmlformats.org/officeDocument/2006/relationships/image",
            "Target": target,
        },
    )
    return ET.tostring(root, encoding="utf-8", xml_declaration=True)


def ensure_png_content_type(content_types: bytes) -> bytes:
    root = ET.fromstring(content_types)
    if not any(item.attrib.get("Extension") == "png" for item in root):
        ET.SubElement(root, xml_tag("ct", "Default"), {"Extension": "png", "ContentType": "image/png"})
    return ET.tostring(root, encoding="utf-8", xml_declaration=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    image_dir = root / "generated"
    images = [image_dir / image for image in SLIDES]
    missing = [str(image) for image in images if not image.is_file()]
    if missing:
        raise FileNotFoundError("Missing approved slide images:\n" + "\n".join(missing))

    template = root / "CICC0900702_北方华创_总决赛_答辩PPT.pptx"
    if not template.is_file():
        raise FileNotFoundError(f"Missing template container: {template}")

    with zipfile.ZipFile(template) as source:
        slide_names = ordered_slide_names(
            [name for name in source.namelist() if re.fullmatch(r"ppt/slides/slide\d+\.xml", name)]
        )
        if len(slide_names) != len(images):
            raise ValueError(f"Template has {len(slide_names)} slides; expected {len(images)}")

        replacement = {
            "[Content_Types].xml": ensure_png_content_type(source.read("[Content_Types].xml")),
            "ppt/presentation.xml": set_widescreen(source.read("ppt/presentation.xml")),
        }
        media: dict[str, bytes] = {}
        for index, (slide_name, image) in enumerate(zip(slide_names, images), start=1):
            replacement[slide_name] = one_full_bleed_picture(source.read(slide_name), image.name)
            relations = f"ppt/slides/_rels/slide{index}.xml.rels"
            media_name = f"ppt/media/cetc_p{index + 2:02d}.png"
            replacement[relations] = add_image_relation(source.read(relations), f"../media/cetc_p{index + 2:02d}.png")
            media[media_name] = image.read_bytes()

        args.output.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(args.output, "w", zipfile.ZIP_DEFLATED) as target:
            for name in source.namelist():
                if name in replacement or name in media:
                    continue
                target.writestr(name, source.read(name))
            for name, data in replacement.items():
                target.writestr(name, data)
            for name, data in media.items():
                target.writestr(name, data)
    return 0


if __name__ == "__main__":
    sys.exit(main())
