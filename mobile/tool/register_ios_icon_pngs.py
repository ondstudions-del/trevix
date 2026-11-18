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
    runner = ios_root / "Runner"
    for name in NAMES:
        if not (runner / name).exists():
            raise SystemExit(f"Falta {runner / name} (ejecuta prepare_alternate_icons.py --ios antes)")

    text = pbx.read_text(encoding="utf-8")

    def _in_resources(n: str) -> bool:
        return f"/* {n} in Resources */" in text

    if all(_in_resources(n) for n in NAMES):
        print("pbxproj ya incluye PNG de iconos alternativos en Resources")
        return

    file_refs: list[tuple[str, str]] = []  # (fileRefId, name)
    build_files: list[tuple[str, str]] = []  # (buildFileId, fileRefId)

    for name in NAMES:
        if _in_resources(name):
            continue
        # Reutilizar fileRef existente si ya está en el proyecto.
        m = re.search(rf"([A-F0-9]{{24}}) /\* {re.escape(name)} \*/ = \{{isa = PBXFileReference;", text)
        fr = m.group(1) if m else _id()
        bf = _id()
        if not m:
            file_refs.append((fr, name))
        build_files.append((bf, fr))

    if not build_files:
        print("Nada que añadir al pbxproj")
        return

    # PBXBuildFile section
    name_by_fr = {fr: name for fr, name in file_refs}
    # Map build files to display names (file_refs may be empty if refs already existed).
    bf_names: list[tuple[str, str, str]] = []
    for bf, fr in build_files:
        name = name_by_fr.get(fr)
        if name is None:
            mname = re.search(rf"{fr} /\* ([^*]+) \*/ = \{{isa = PBXFileReference;", text)
            name = mname.group(1).strip() if mname else "icon.png"
        bf_names.append((bf, fr, name))

    build_block = "".join(
        f"\t\t{bf} /* {name} in Resources */ = {{isa = PBXBuildFile; fileRef = {fr} /* {name} */; }};\n"
        for bf, fr, name in bf_names
    )
    text = text.replace(
        "/* Begin PBXBuildFile section */\n",
        "/* Begin PBXBuildFile section */\n" + build_block,
        1,
    )

    # PBXFileReference section (solo los nuevos)
    if file_refs:
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
    insert = "".join(f"\n\t\t\t\t{bf} /* {name} in Resources */," for bf, _, name in bf_names)
    start = m.end(1)
    text = text[:start] + insert + text[start:]

    pbx.write_text(text, encoding="utf-8")
    missing = [n for n in NAMES if f"/* {n} in Resources */" not in text]
    if missing:
        raise SystemExit(f"pbxproj incompleto: faltan en Resources: {', '.join(missing)}")
    print(f"pbxproj: registrados {len(bf_names)} PNG de iconos en Resources")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("ios", type=Path)
    args = p.parse_args()
    register(args.ios)


if __name__ == "__main__":
    main()
