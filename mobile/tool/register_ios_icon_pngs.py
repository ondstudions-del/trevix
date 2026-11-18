#!/usr/bin/env python3
"""Registra AppIcon*@2x/3x.png de Runner/ en Copy Bundle Resources del target Runner.

Uso: python tool/register_ios_icon_pngs.py ios
"""

from __future__ import annotations

import argparse
import re
import uuid
from pathlib import Path

NAMES = [
    "AppIconWave@2x.png",
    "AppIconWave@3x.png",
    "AppIconHeart@2x.png",
    "AppIconHeart@3x.png",
    "AppIconMessages@2x.png",
    "AppIconMessages@3x.png",
    "AppIconMark@2x.png",
    "AppIconMark@3x.png",
]


def _id() -> str:
    return uuid.uuid4().hex[:24].upper()


def register(ios_root: Path) -> None:
    pbx = ios_root / "Runner.xcodeproj" / "project.pbxproj"
    if not pbx.exists():
        raise SystemExit(f"No está {pbx}")
    text = pbx.read_text(encoding="utf-8")
    if "AppIconWave@2x.png" in text and "in Resources" in text:
        # Ya hay referencias; si faltan build files, seguir.
        if all(n in text for n in NAMES):
            print("pbxproj ya incluye PNG de iconos alternativos")
            return

    file_refs: list[tuple[str, str]] = []  # (fileRefId, name)
    build_files: list[tuple[str, str]] = []  # (buildFileId, fileRefId)

    for name in NAMES:
        if name in text and f"/* {name} */" in text:
            continue
        fr = _id()
        bf = _id()
        file_refs.append((fr, name))
        build_files.append((bf, fr))

    if not file_refs:
        print("Nada que añadir al pbxproj")
        return

    # PBXBuildFile section
    build_block = "".join(
        f"\t\t{bf} /* {name} in Resources */ = {{isa = PBXBuildFile; fileRef = {fr} /* {name} */; }};\n"
        for (bf, fr), (_, name) in zip(build_files, file_refs)
    )
    text = text.replace(
        "/* Begin PBXBuildFile section */\n",
        "/* Begin PBXBuildFile section */\n" + build_block,
        1,
    )

    # PBXFileReference section
    ref_block = "".join(
        f'\t\t{fr} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = image.png; '
        f'name = "{name}"; path = "{name}"; sourceTree = "<group>"; }};\n'
        for fr, name in file_refs
    )
    text = text.replace(
        "/* Begin PBXFileReference section */\n",
        "/* Begin PBXFileReference section */\n" + ref_block,
        1,
    )

    # Add to Runner group children (look for AppDelegate.swift in group)
    for fr, name in file_refs:
        marker = "AppDelegate.swift */,"
        if marker in text and f"{fr} /* {name} */," not in text:
            text = text.replace(
                marker,
                f"AppDelegate.swift */,\n\t\t\t\t{fr} /* {name} */,",
                1,
            )

    # Add to Resources build phase
    m = re.search(r"(/\* Resources \*/ = \{\s*isa = PBXResourcesBuildPhase;.*?files = \()", text, re.S)
    if not m:
        raise SystemExit("No se encontró PBXResourcesBuildPhase")
    insert = "".join(f"\n\t\t\t\t{bf} /* {name} in Resources */," for (bf, _), (_, name) in zip(build_files, file_refs))
    start = m.end(1)
    text = text[:start] + insert + text[start:]

    # Verify PNGs exist
    runner = ios_root / "Runner"
    for name in NAMES:
        if not (runner / name).exists():
            raise SystemExit(f"Falta {runner / name} (ejecuta prepare_alternate_icons.py --ios antes)")

    pbx.write_text(text, encoding="utf-8")
    print(f"pbxproj: registrados {len(file_refs)} PNG de iconos")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("ios", type=Path)
    args = p.parse_args()
    register(args.ios)


if __name__ == "__main__":
    main()
