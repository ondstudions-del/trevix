#!/usr/bin/env python3
"""Comprueba que el .app incluye iconos alternativos listos para setAlternateIconName.

Uso: python tool/verify_ios_alternate_icons.py build/ios/iphoneos/Runner.app
"""

from __future__ import annotations

import argparse
import plistlib
import sys
from pathlib import Path

NAMES = ["AppIconWave", "AppIconHeart", "AppIconMessages", "AppIconMark"]


def verify(app: Path) -> None:
    if not app.is_dir():
        raise SystemExit(f"No es un directorio: {app}")
    plist = app / "Info.plist"
    if not plist.exists():
        raise SystemExit(f"Falta {plist}")
    with plist.open("rb") as f:
        info = plistlib.load(f)
    icons = info.get("CFBundleIcons") or {}
    alt = (icons.get("CFBundleAlternateIcons") or {})
    assets = app / "Assets.car"
    if not assets.exists():
        print(f"::warning::No hay Assets.car en {app} (¿compilación sin asset catalog?)")
    for name in NAMES:
        entry = alt.get(name)
        if not entry:
            raise SystemExit(f"Info.plist sin CFBundleAlternateIcons.{name}")
        icon_name = entry.get("CFBundleIconName")
        files = entry.get("CFBundleIconFiles")
        if not icon_name and not files:
            raise SystemExit(f"{name}: falta CFBundleIconName o CFBundleIconFiles")
        if icon_name and icon_name != name:
            raise SystemExit(f"{name}: CFBundleIconName={icon_name!r} no coincide")
        file_stem = name
        if files:
            file_stem = str(files[0])
        for suf in ("@2x", "@3x"):
            p = app / f"{file_stem}{suf}.png"
            if not p.exists():
                raise SystemExit(f"Falta PNG suelto en bundle: {p.name}")
            if p.stat().st_size < 500:
                raise SystemExit(f"PNG demasiado pequeño: {p.name}")
    print(f"OK: iconos alternativos en {app} (PNG en bundle + Info.plist)")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("app", type=Path)
    args = p.parse_args()
    try:
        verify(args.app)
    except SystemExit as e:
        print(f"::error::{e}", file=sys.stderr)
        raise


if __name__ == "__main__":
    main()