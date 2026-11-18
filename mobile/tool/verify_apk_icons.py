#!/usr/bin/env python3
"""Comprueba en un APK que los adaptive de iconos alt no sean circulares."""
from __future__ import annotations

import re
import sys
import zipfile
from pathlib import Path

KEYS = ("wave", "heart", "messages", "mark")


def main() -> int:
    apk = Path(sys.argv[1] if len(sys.argv) > 1 else Path.home() / "Desktop" / "TREVIX.apk")
    if not apk.exists():
        print(f"No está {apk}", file=sys.stderr)
        return 1
    circular = []
    missing_fg = []
    with zipfile.ZipFile(apk) as z:
        xmls = [n for n in z.namelist() if "mipmap-anydpi" in n and n.endswith(".xml")]
        for n in sorted(xmls):
            text = z.read(n).decode("utf-8", "replace")
            print(f"=== {n} ===")
            print(text.rstrip())
            for key in KEYS:
                if f"ic_launcher_{key}" not in Path(n).stem and f"ic_launcher_{key}_round" not in Path(n).stem:
                    continue
                # Circular: foreground apunta al mismo mipmap base (sin _foreground).
                if re.search(rf'foreground[^>]*@mipmap/ic_launcher_{key}"', text) or re.search(
                    rf'android:drawable="@mipmap/ic_launcher_{key}"', text
                ):
                    if f"ic_launcher_{key}_foreground" not in text:
                        circular.append(n)
                if f"ic_launcher_{key}_foreground" not in text and "ic_launcher_" + key in Path(n).name:
                    missing_fg.append(n)
        fg_png = [n for n in z.namelist() if re.search(r"ic_launcher_(wave|heart|messages|mark)_foreground\.png$", n)]
        round_xml = [n for n in xmls if n.endswith("_round.xml")]
        print(f"\nforeground pngs: {len(fg_png)}")
        print(f"round xmls: {len(round_xml)}")
        for n in sorted(fg_png)[:8]:
            print(" ", n)
    if circular:
        print("CIRCULAR:", *circular, sep="\n  ")
        return 2
    if missing_fg:
        print("MISSING_FG:", *missing_fg, sep="\n  ")
        return 3
    print("OK: sin referencia circular; foreground separado presente.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
